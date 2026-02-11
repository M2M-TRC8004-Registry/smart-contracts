// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEnhancedIdentityRegistry {
    function exists(uint256 tokenId) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
    function agentWalletOf(uint256 tokenId) external view returns (address);
}

/**
 * @title ValidationRegistry
 * @notice Validation workflow for M2M TRC-8004 AI agent capabilities
 * 
 * Key improvements:
 * - Fixed hash confusion: requestId vs requestDataHash
 * - Added cancelRequest() for requesters
 * - Agent existence enforced
 * - Complete/Reject/Cancel workflow
 */
contract ValidationRegistry {
    enum ValidationStatus { Pending, Completed, Rejected, Cancelled }

    struct ValidationRequest {
        bytes32 requestId;          // Unique identifier
        bytes32 requestDataHash;    // Hash of request payload for integrity

        address requester;
        address validator;
        uint256 agentId;

        string requestURI;          // Off-chain details
        uint256 timestamp;

        ValidationStatus status;
        string resultURI;           // Validator's result
        bytes32 resultHash;         // Validator result hash
        uint256 completedAt;
    }

    IEnhancedIdentityRegistry public immutable identityRegistry;

    mapping(bytes32 => ValidationRequest) private _requests;

    mapping(address => bytes32[]) private _requestsByRequester;
    mapping(address => bytes32[]) private _requestsByValidator;
    mapping(uint256 => bytes32[]) private _requestsByAgent;

    mapping(address => uint256) public requesterNonce;

    event ValidationRequested(bytes32 indexed requestId, uint256 indexed agentId, address indexed validator, address requester);
    event ValidationCompleted(bytes32 indexed requestId, uint256 indexed agentId, address indexed validator);
    event ValidationRejected(bytes32 indexed requestId, uint256 indexed agentId, address indexed validator);
    event ValidationCancelled(bytes32 indexed requestId, uint256 indexed agentId, address indexed requester);

    constructor(address identityRegistryAddress) {
        require(identityRegistryAddress != address(0), "Zero identity registry");
        identityRegistry = IEnhancedIdentityRegistry(identityRegistryAddress);
    }

    /// @notice Create a validation request
    function validationRequest(
        uint256 agentId,
        address validator,
        string calldata requestURI,
        bytes32 requestDataHash
    ) external returns (bytes32 requestId) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(validator != address(0), "Zero validator");

        // Ensure consistent data hash
        bytes32 dataHash = requestDataHash;
        if (dataHash == bytes32(0)) {
            dataHash = keccak256(abi.encodePacked(msg.sender, validator, agentId, requestURI));
        }

        // Generate unique requestId (separate from dataHash)
        uint256 nonce = requesterNonce[msg.sender]++;
        requestId = keccak256(abi.encodePacked(msg.sender, validator, agentId, dataHash, nonce, block.chainid));

        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp == 0, "Duplicate requestId");

        r.requestId = requestId;
        r.requestDataHash = dataHash;
        r.requester = msg.sender;
        r.validator = validator;
        r.agentId = agentId;
        r.requestURI = requestURI;
        r.timestamp = block.timestamp;
        r.status = ValidationStatus.Pending;

        _requestsByRequester[msg.sender].push(requestId);
        _requestsByValidator[validator].push(requestId);
        _requestsByAgent[agentId].push(requestId);

        emit ValidationRequested(requestId, agentId, validator, msg.sender);
    }

    function cancelRequest(bytes32 requestId) external {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        require(r.requester == msg.sender, "Not requester");
        require(r.status == ValidationStatus.Pending, "Not pending");

        r.status = ValidationStatus.Cancelled;
        emit ValidationCancelled(requestId, r.agentId, msg.sender);
    }

    function completeValidation(
        bytes32 requestId,
        string calldata resultURI,
        bytes32 resultHash
    ) external {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        require(r.status == ValidationStatus.Pending, "Not pending");
        require(msg.sender == r.validator, "Not validator");

        r.status = ValidationStatus.Completed;
        r.resultURI = resultURI;
        r.resultHash = resultHash;
        r.completedAt = block.timestamp;

        emit ValidationCompleted(requestId, r.agentId, msg.sender);
    }

    function rejectValidation(bytes32 requestId, string calldata resultURI, bytes32 reasonHash) external {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        require(r.status == ValidationStatus.Pending, "Not pending");
        require(msg.sender == r.validator, "Not validator");

        r.status = ValidationStatus.Rejected;
        r.resultURI = resultURI;
        r.resultHash = reasonHash;
        r.completedAt = block.timestamp;

        emit ValidationRejected(requestId, r.agentId, msg.sender);
    }

    // --- Views ---

    function getRequest(bytes32 requestId) external view returns (ValidationRequest memory) {
        ValidationRequest memory r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        return r;
    }

    function getRequesterRequests(address requester) external view returns (bytes32[] memory) {
        return _requestsByRequester[requester];
    }

    function getValidatorRequests(address validator) external view returns (bytes32[] memory) {
        return _requestsByValidator[validator];
    }

    function getAgentRequests(uint256 agentId) external view returns (bytes32[] memory) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        return _requestsByAgent[agentId];
    }

    function getSummaryForAgent(uint256 agentId) external view returns (
        uint256 total,
        uint256 pending,
        uint256 completed,
        uint256 rejected,
        uint256 cancelled
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        bytes32[] storage ids = _requestsByAgent[agentId];
        total = ids.length;

        for (uint256 i = 0; i < ids.length; i++) {
            ValidationStatus st = _requests[ids[i]].status;
            if (st == ValidationStatus.Pending) pending++;
            else if (st == ValidationStatus.Completed) completed++;
            else if (st == ValidationStatus.Rejected) rejected++;
            else if (st == ValidationStatus.Cancelled) cancelled++;
        }
    }
}
