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
 * @title EnhancedIdentityRegistry (TRC-8004 v2)
 * @notice Full ERC-721 + ERC-8004 compatible agent identity registry on TRON
 *
 * ERC-8004 Compatibility Additions:
 * - register() overloads: no-arg, URI-only, URI+MetadataEntry[]
 * - setAgentURI() with URIUpdated event
 * - setMetadata() per-key with bytes values + MetadataSet event
 * - setAgentWallet() with EIP-712 signature verification + deadline
 * - unsetAgentWallet()
 * - Auto-clear agentWallet on transfer
 * - agentExists() / getAgentWallet() aliases
 * - Aligned event signatures (Registered, AgentWalletSet)
 *
 * TRC-8004 Extensions (kept):
 * - metadataHashOf (on-chain integrity check)
 * - registerWithOnChainMetadata (batch metadata at registration)
 * - deactivate/reactivate/isActive (agent lifecycle)
 */
contract EnhancedIdentityRegistry is IERC165 {
    // --- String length limits (security hardening) ---
    uint256 public constant MAX_URI_LENGTH = 2048;
    uint256 public constant MAX_KEY_LENGTH = 128;

    // --- Structs ---
    struct MetadataEntry {
        string key;
        bytes value;
    }

    // --- Events (ERC-8004 aligned) ---
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice ERC-8004 aligned: Registered(agentId, agentURI, owner)
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);

    /// @notice TRC-8004 extension: includes metadataHash (kept for backward compat)
    event AgentRegistered(uint256 indexed agentId, address indexed owner, string tokenURI, bytes32 metadataHash);

    /// @notice ERC-8004: URIUpdated
    event URIUpdated(uint256 indexed agentId, string newURI);

    /// @notice ERC-8004: MetadataSet per-key
    event MetadataSet(uint256 indexed agentId, string key, bytes value);

    /// @notice ERC-8004 aligned: AgentWalletSet includes setBy
    event AgentWalletSet(uint256 indexed agentId, address indexed agentWallet, address indexed setBy);

    /// @notice TRC-8004 legacy event (kept for backward compat)
    event AgentWalletUpdated(uint256 indexed agentId, address indexed agentWallet);

    /// @notice TRC-8004 extension: agent deactivation events
    event AgentDeactivated(uint256 indexed agentId, address indexed deactivatedBy);
    event AgentReactivated(uint256 indexed agentId, address indexed reactivatedBy);

    // --- EIP-712 ---
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant SET_AGENT_WALLET_TYPEHASH =
        keccak256("SetAgentWallet(uint256 agentId,address wallet,uint256 nonce,uint256 deadline)");

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
    mapping(uint256 => mapping(string => bytes)) private _metadataKV;
    mapping(uint256 => address) private _agentWallet;
    mapping(uint256 => bool) private _deactivated;
    mapping(uint256 => uint256) public walletDelegationNonce;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    // --- ERC165 ---
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f;   // ERC721Metadata
    }

    // --- Existence helpers ---

    /// @notice Original TRC-8004 existence check
    function exists(uint256 tokenId) public view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /// @notice ERC-8004 compatible alias
    function agentExists(uint256 tokenId) external view returns (bool) {
        return exists(tokenId);
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

    /// @notice Original TRC-8004 wallet getter
    function agentWalletOf(uint256 tokenId) public view returns (address) {
        require(exists(tokenId), "Nonexistent token");
        return _agentWallet[tokenId];
    }

    /// @notice ERC-8004 compatible alias
    function getAgentWallet(uint256 tokenId) external view returns (address) {
        return agentWalletOf(tokenId);
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

    // --- Transfers (auto-clear agentWallet on transfer) ---
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(to != address(0), "Zero address");
        address owner = ownerOf(tokenId);
        require(owner == from, "From not owner");
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");

        _clearApproval(tokenId);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        // ERC-8004: Clear agent wallet on transfer for security
        if (_agentWallet[tokenId] != address(0)) {
            _agentWallet[tokenId] = address(0);
            emit AgentWalletSet(tokenId, address(0), address(this));
            emit AgentWalletUpdated(tokenId, address(0));
        }

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);

        if (to.code.length > 0) {
            bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data);
            require(retval == IERC721Receiver.onERC721Received.selector, "Unsafe recipient");
        }
    }

    // ==========================================================================
    // Registration (ERC-8004 overloads + TRC-8004 extensions)
    // ==========================================================================

    /// @notice ERC-8004: No-arg registration — mints with empty URI
    function register() external returns (uint256 agentId) {
        agentId = _mint(msg.sender, "");
        emit Registered(agentId, "", msg.sender);
    }

    /// @notice ERC-8004: URI-only registration
    function registerWithURI(string calldata agentURI) external returns (uint256 agentId) {
        require(bytes(agentURI).length <= MAX_URI_LENGTH, "URI too long");
        agentId = _mint(msg.sender, agentURI);
        emit Registered(agentId, agentURI, msg.sender);
    }

    /// @notice ERC-8004: URI + MetadataEntry[] registration
    function registerWithMetadata(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId) {
        require(bytes(agentURI).length <= MAX_URI_LENGTH, "URI too long");
        agentId = _mint(msg.sender, agentURI);

        for (uint256 i = 0; i < metadata.length; i++) {
            require(bytes(metadata[i].key).length <= MAX_KEY_LENGTH, "Key too long");
            _metadataKV[agentId][metadata[i].key] = metadata[i].value;
            emit MetadataSet(agentId, metadata[i].key, metadata[i].value);
        }

        emit Registered(agentId, agentURI, msg.sender);
    }

    /// @notice TRC-8004 original: register(uri, metadataHash) — kept for backward compatibility
    function register(string calldata uri, bytes32 _metadataHash) external returns (uint256 agentId) {
        require(bytes(uri).length <= MAX_URI_LENGTH, "URI too long");
        agentId = _mint(msg.sender, uri);
        metadataHashOf[agentId] = _metadataHash;
        emit Registered(agentId, uri, msg.sender);
        emit AgentRegistered(agentId, msg.sender, uri, _metadataHash);
    }

    /// @notice TRC-8004 extension: batch metadata at registration (updated to bytes values)
    function registerWithOnChainMetadata(
        string calldata uri,
        bytes32 _metadataHash,
        string[] calldata keys,
        bytes[] calldata values
    ) external returns (uint256 agentId) {
        require(keys.length == values.length, "KV length mismatch");
        require(bytes(uri).length <= MAX_URI_LENGTH, "URI too long");

        agentId = _mint(msg.sender, uri);
        metadataHashOf[agentId] = _metadataHash;

        for (uint256 i = 0; i < keys.length; i++) {
            require(bytes(keys[i]).length <= MAX_KEY_LENGTH, "Key too long");
            _metadataKV[agentId][keys[i]] = values[i];
            emit MetadataSet(agentId, keys[i], values[i]);
        }

        emit Registered(agentId, uri, msg.sender);
        emit AgentRegistered(agentId, msg.sender, uri, _metadataHash);
    }

    // ==========================================================================
    // URI & Metadata Updates
    // ==========================================================================

    /// @notice ERC-8004: Update agent URI post-registration
    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(exists(agentId), "Nonexistent token");
        require(bytes(newURI).length <= MAX_URI_LENGTH, "URI too long");
        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");

        _tokenURIs[agentId] = newURI;
        emit URIUpdated(agentId, newURI);
    }

    /// @notice ERC-8004: Per-key metadata setter with bytes values
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external {
        require(exists(agentId), "Nonexistent token");
        require(bytes(key).length <= MAX_KEY_LENGTH, "Key too long");
        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");

        _metadataKV[agentId][key] = value;
        emit MetadataSet(agentId, key, value);
    }

    /// @notice ERC-8004: Get metadata value (returns bytes)
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory) {
        require(exists(agentId), "Nonexistent token");
        return _metadataKV[agentId][key];
    }

    /// @notice TRC-8004 legacy: Get metadata value as string (backward compat)
    function getMetadataValue(uint256 agentId, string calldata key) external view returns (string memory) {
        require(exists(agentId), "Nonexistent token");
        return string(_metadataKV[agentId][key]);
    }

    // ==========================================================================
    // Agent Wallet Delegation
    // ==========================================================================

    /// @notice ERC-8004: Set agent wallet with EIP-712 signature verification
    function setAgentWalletSigned(
        uint256 agentId,
        address wallet,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(exists(agentId), "Nonexistent token");
        require(block.timestamp <= deadline, "Signature expired");

        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");

        // Verify wallet's signature (proof of control) with nonce for replay protection
        if (wallet != address(0)) {
            // EIP-2 canonical signature enforcement (prevents malleability)
            require(v == 27 || v == 28, "Invalid v value");
            require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "Invalid s value");

            uint256 nonce = walletDelegationNonce[agentId]++;
            bytes32 structHash = keccak256(abi.encode(SET_AGENT_WALLET_TYPEHASH, agentId, wallet, nonce, deadline));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
            address recovered = ecrecover(digest, v, r, s);
            require(recovered != address(0), "Invalid signature");
            require(recovered == wallet, "Invalid wallet signature");
        }

        _agentWallet[agentId] = wallet;
        emit AgentWalletSet(agentId, wallet, msg.sender);
        emit AgentWalletUpdated(agentId, wallet);
    }

    /// @notice TRC-8004 legacy: setAgentWallet — can only UNSET (set to address(0)).
    ///         To set a non-zero wallet, use setAgentWalletSigned() for proof-of-control.
    function setAgentWallet(uint256 agentId, address wallet) external {
        require(exists(agentId), "Nonexistent token");
        require(wallet == address(0), "Use setAgentWalletSigned for non-zero wallet");
        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");
        _agentWallet[agentId] = address(0);
        emit AgentWalletSet(agentId, address(0), msg.sender);
        emit AgentWalletUpdated(agentId, address(0));
    }

    /// @notice ERC-8004: Clear agent wallet
    function unsetAgentWallet(uint256 agentId) external {
        require(exists(agentId), "Nonexistent token");
        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");

        _agentWallet[agentId] = address(0);
        emit AgentWalletSet(agentId, address(0), msg.sender);
        emit AgentWalletUpdated(agentId, address(0));
    }

    // ==========================================================================
    // Agent Lifecycle (TRC-8004 Extension)
    // ==========================================================================

    /// @notice Deactivate an agent (owner-only)
    function deactivate(uint256 agentId) external {
        require(exists(agentId), "Nonexistent token");
        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");
        require(!_deactivated[agentId], "Already deactivated");

        _deactivated[agentId] = true;
        emit AgentDeactivated(agentId, msg.sender);
    }

    /// @notice Reactivate an agent (owner-only)
    function reactivate(uint256 agentId) external {
        require(exists(agentId), "Nonexistent token");
        address owner = ownerOf(agentId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");
        require(_deactivated[agentId], "Not deactivated");

        _deactivated[agentId] = false;
        emit AgentReactivated(agentId, msg.sender);
    }

    /// @notice Check if agent is active
    function isActive(uint256 agentId) external view returns (bool) {
        require(exists(agentId), "Nonexistent token");
        return !_deactivated[agentId];
    }

    // --- Internals ---
    function _mint(address to, string memory uri) internal returns (uint256 tokenId) {
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
