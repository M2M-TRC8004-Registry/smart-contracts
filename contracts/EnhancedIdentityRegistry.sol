// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal ERC165
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice Minimal ERC721Receiver for safe transfers
interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/**
 * @title EnhancedIdentityRegistry
 * @notice Full ERC-721 implementation for M2M TRC-8004 AI agent ownership
 * 
 * Key improvements:
 * - Proper safeTransferFrom with ERC721Receiver check (CRITICAL FIX)
 * - Agent wallet delegation for operational separation
 * - Explicit exists() helper for other contracts  
 * - Constructor for name/symbol configuration
 */
contract EnhancedIdentityRegistry is IERC165 {
    // --- Events ---
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event AgentRegistered(uint256 indexed agentId, address indexed owner, string tokenURI, bytes32 metadataHash);
    event AgentWalletUpdated(uint256 indexed agentId, address indexed agentWallet);

    // --- Storage ---
    string public name;
    string public symbol;

    uint256 private _nextTokenId = 1;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => bytes32) public metadataHashOf;
    mapping(uint256 => mapping(string => string)) private _metadataKV;
    mapping(uint256 => address) private _agentWallet;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    // --- ERC165 ---
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f;   // ERC721Metadata
    }

    // --- Existence helper (for other contracts) ---
    function exists(uint256 tokenId) public view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    // --- ERC721 views ---
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "Zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Nonexistent token");
        return owner;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(exists(tokenId), "Nonexistent token");
        return _tokenURIs[tokenId];
    }

    function agentWalletOf(uint256 tokenId) public view returns (address) {
        require(exists(tokenId), "Nonexistent token");
        return _agentWallet[tokenId];
    }

    function totalAgents() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    // --- Approvals ---
    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(to != owner, "Approval to current owner");
        require(
            msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "Not owner nor approved for all"
        );
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(exists(tokenId), "Nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        require(operator != msg.sender, "Approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    // --- Transfers ---
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(to != address(0), "Zero address");
        address owner = ownerOf(tokenId);
        require(owner == from, "From not owner");
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");

        _clearApproval(tokenId);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);

        // CRITICAL FIX: ERC721Receiver check prevents NFTs getting stuck in contracts
        if (to.code.length > 0) {
            bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data);
            require(retval == IERC721Receiver.onERC721Received.selector, "Unsafe recipient");
        }
    }

    // --- Registration ---
    function register(string calldata uri, bytes32 metadataHash) external returns (uint256 agentId) {
        agentId = _mint(msg.sender, uri);
        metadataHashOf[agentId] = metadataHash;
        emit AgentRegistered(agentId, msg.sender, uri, metadataHash);
    }

    function registerWithOnChainMetadata(
        string calldata uri,
        bytes32 metadataHash,
        string[] calldata keys,
        string[] calldata values
    ) external returns (uint256 agentId) {
        require(keys.length == values.length, "KV length mismatch");

        agentId = _mint(msg.sender, uri);
        metadataHashOf[agentId] = metadataHash;

        for (uint256 i = 0; i < keys.length; i++) {
            _metadataKV[agentId][keys[i]] = values[i];
        }

        emit AgentRegistered(agentId, msg.sender, uri, metadataHash);
    }

    function getMetadataValue(uint256 agentId, string calldata key) external view returns (string memory) {
        require(exists(agentId), "Nonexistent token");
        return _metadataKV[agentId][key];
    }

    /// @notice Delegate an agent wallet for operational actions
    function setAgentWallet(uint256 agentId, address wallet) external {
        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");
        _agentWallet[agentId] = wallet;
        emit AgentWalletUpdated(agentId, wallet);
    }

    // --- Internals ---
    function _mint(address to, string calldata uri) internal returns (uint256 tokenId) {
        require(to != address(0), "Zero address");
        tokenId = _nextTokenId++;
        _owners[tokenId] = to;
        _balances[to] += 1;
        _tokenURIs[tokenId] = uri;
        emit Transfer(address(0), to, tokenId);
    }

    function _clearApproval(uint256 tokenId) internal {
        if (_tokenApprovals[tokenId] != address(0)) {
            _tokenApprovals[tokenId] = address(0);
            emit Approval(ownerOf(tokenId), address(0), tokenId);
        }
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (
            spender == owner ||
            spender == getApproved(tokenId) ||
            isApprovedForAll(owner, spender)
        );
    }
}
