// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEnhancedIdentityRegistry {
    function exists(uint256 tokenId) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
    function agentWalletOf(uint256 tokenId) external view returns (address);
}

/**
 * @title ValidationRegistry (TRC-8004 v2)
 * @notice Validation workflow — ERC-8004 compatible superset
 *
 * ERC-8004 Compatibility Additions:
 * - tag field on responses (categorization)
 * - response numeric value (uint8, 0-100) alongside status
 * - requestExists() convenience function
 * - getValidationStatus() spec-compatible view
 * - getIdentityRegistry() getter
 * - Spec param order alias for validationRequest()
 * - Filtered getSummary(agentId, validators[], tag)
 * - Spec events alongside our split events
 *
 * TRC-8004 Extensions (kept):
 * - cancelRequest() — validation lifecycle
 * - Deterministic requestId generation (collision-free)
 * - getRequesterRequests() — requester-indexed queries
 * - Full struct getRequest() — on-chain composability
 * - getSummaryForAgent() — unfiltered status counts
 */
contract ValidationRegistry {
    // --- String length limits (security hardening) ---
    uint256 public constant MAX_URI_LENGTH = 2048;
    uint256 public constant MAX_TAG_LENGTH = 128;

    enum ValidationStatus { Pending, Completed, Rejected, Cancelled }

    struct ValidationRequest {
        bytes32 requestId;
        bytes32 requestDataHash;

        address requester;
        address validator;
        uint256 agentId;

        string requestURI;
        uint256 timestamp;

        ValidationStatus status;
        string resultURI;
        bytes32 resultHash;
        uint256 completedAt;

        // ERC-8004 compat additions
        string tag;
        uint8 response;     // 0-100 numeric response value
    }

    IEnhancedIdentityRegistry public immutable identityRegistry;

    mapping(bytes32 => ValidationRequest) private _requests;

    mapping(address => bytes32[]) private _requestsByRequester;
    mapping(address => bytes32[]) private _requestsByValidator;
    mapping(uint256 => bytes32[]) private _requestsByAgent;

    mapping(address => uint256) public requesterNonce;

    // TRC-8004 split events (kept)
    event ValidationRequested(bytes32 indexed requestId, uint256 indexed agentId, address indexed validator, address requester);
    event ValidationCompleted(bytes32 indexed requestId, uint256 indexed agentId, address indexed validator);
    event ValidationRejected(bytes32 indexed requestId, uint256 indexed agentId, address indexed validator);
    event ValidationCancelled(bytes32 indexed requestId, uint256 indexed agentId, address indexed requester);

    // ERC-8004 unified events (added)
    event ValidationResponse(
        bytes32 indexed requestId,
        uint256 indexed agentId,
        address indexed validator,
        uint8 response,
        string tag,
        string resultURI,
        bytes32 resultHash
    );

    constructor(address identityRegistryAddress) {
        require(identityRegistryAddress != address(0), "Zero identity registry");
        identityRegistry = IEnhancedIdentityRegistry(identityRegistryAddress);
    }

    /// @notice ERC-8004 getter for linked registry
    function getIdentityRegistry() external view returns (address) {
        return address(identityRegistry);
    }

    /// @notice Create a validation request (TRC-8004 param order: agentId, validator)
    function validationRequest(
        uint256 agentId,
        address validator,
        string calldata requestURI,
        bytes32 requestDataHash
    ) external returns (bytes32 requestId) {
        return _createRequest(agentId, validator, requestURI, requestDataHash);
    }

    /// @notice ERC-8004 param order alias: validator, agentId
    function validationRequest(
        address validator,
        uint256 agentId,
        string calldata requestURI,
        bytes32 requestDataHash
    ) external returns (bytes32 requestId) {
        return _createRequest(agentId, validator, requestURI, requestDataHash);
    }

    function _createRequest(
        uint256 agentId,
        address validator,
        string calldata requestURI,
        bytes32 requestDataHash
    ) internal returns (bytes32 requestId) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(validator != address(0), "Zero validator");
        require(bytes(requestURI).length <= MAX_URI_LENGTH, "URI too long");

        bytes32 dataHash = requestDataHash;
        if (dataHash == bytes32(0)) {
            dataHash = keccak256(abi.encode(msg.sender, validator, agentId, requestURI));
        }

        uint256 nonce = requesterNonce[msg.sender]++;
        requestId = keccak256(abi.encode(msg.sender, validator, agentId, dataHash, nonce, block.chainid));

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

    /// @notice Complete validation with tag + response value (ERC-8004 compat)
    function completeValidation(
        bytes32 requestId,
        string calldata resultURI,
        bytes32 resultHash,
        string calldata tag,
        uint8 response
    ) external {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        require(r.status == ValidationStatus.Pending, "Not pending");
        require(msg.sender == r.validator, "Not validator");
        require(bytes(resultURI).length <= MAX_URI_LENGTH, "URI too long");
        require(bytes(tag).length <= MAX_TAG_LENGTH, "Tag too long");

        r.status = ValidationStatus.Completed;
        r.resultURI = resultURI;
        r.resultHash = resultHash;
        r.completedAt = block.timestamp;
        r.tag = tag;
        r.response = response;

        emit ValidationCompleted(requestId, r.agentId, msg.sender);
        emit ValidationResponse(requestId, r.agentId, msg.sender, response, tag, resultURI, resultHash);
    }

    /// @notice TRC-8004 legacy: completeValidation without tag/response (backward compat)
    function completeValidation(
        bytes32 requestId,
        string calldata resultURI,
        bytes32 resultHash
    ) external {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        require(r.status == ValidationStatus.Pending, "Not pending");
        require(msg.sender == r.validator, "Not validator");
        require(bytes(resultURI).length <= MAX_URI_LENGTH, "URI too long");

        r.status = ValidationStatus.Completed;
        r.resultURI = resultURI;
        r.resultHash = resultHash;
        r.completedAt = block.timestamp;
        r.response = 100; // Default: completed = 100

        emit ValidationCompleted(requestId, r.agentId, msg.sender);
        emit ValidationResponse(requestId, r.agentId, msg.sender, 100, "", resultURI, resultHash);
    }

    /// @notice Reject validation with tag + response value (ERC-8004 compat)
    function rejectValidation(
        bytes32 requestId,
        string calldata resultURI,
        bytes32 reasonHash,
        string calldata tag,
        uint8 response
    ) external {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        require(r.status == ValidationStatus.Pending, "Not pending");
        require(msg.sender == r.validator, "Not validator");
        require(bytes(resultURI).length <= MAX_URI_LENGTH, "URI too long");
        require(bytes(tag).length <= MAX_TAG_LENGTH, "Tag too long");

        r.status = ValidationStatus.Rejected;
        r.resultURI = resultURI;
        r.resultHash = reasonHash;
        r.completedAt = block.timestamp;
        r.tag = tag;
        r.response = response;

        emit ValidationRejected(requestId, r.agentId, msg.sender);
        emit ValidationResponse(requestId, r.agentId, msg.sender, response, tag, resultURI, reasonHash);
    }

    /// @notice TRC-8004 legacy: rejectValidation without tag/response (backward compat)
    function rejectValidation(bytes32 requestId, string calldata resultURI, bytes32 reasonHash) external {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        require(r.status == ValidationStatus.Pending, "Not pending");
        require(msg.sender == r.validator, "Not validator");
        require(bytes(resultURI).length <= MAX_URI_LENGTH, "URI too long");

        r.status = ValidationStatus.Rejected;
        r.resultURI = resultURI;
        r.resultHash = reasonHash;
        r.completedAt = block.timestamp;
        r.response = 0; // Default: rejected = 0

        emit ValidationRejected(requestId, r.agentId, msg.sender);
        emit ValidationResponse(requestId, r.agentId, msg.sender, 0, "", resultURI, reasonHash);
    }

    // --- Views ---

    function getRequest(bytes32 requestId) external view returns (ValidationRequest memory) {
        ValidationRequest memory r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        return r;
    }

    /// @notice ERC-8004: Check if request exists
    function requestExists(bytes32 requestId) external view returns (bool) {
        return _requests[requestId].timestamp != 0;
    }

    /// @notice ERC-8004: Get validation status
    function getValidationStatus(bytes32 requestId) external view returns (
        ValidationStatus status,
        uint8 response,
        string memory tag,
        string memory resultURI,
        bytes32 resultHash
    ) {
        ValidationRequest storage r = _requests[requestId];
        require(r.timestamp != 0, "Unknown request");
        return (r.status, r.response, r.tag, r.resultURI, r.resultHash);
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

    /// @notice TRC-8004: Unfiltered summary — returns status counts + avg response
    function getSummaryForAgent(uint256 agentId) external view returns (
        uint256 total,
        uint256 pending,
        uint256 completed,
        uint256 rejected,
        uint256 cancelled,
        uint256 responseSum,
        uint256 responseCount
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        bytes32[] storage ids = _requestsByAgent[agentId];
        total = ids.length;

        for (uint256 i = 0; i < ids.length; i++) {
            ValidationRequest storage r = _requests[ids[i]];
            if (r.status == ValidationStatus.Pending) pending++;
            else if (r.status == ValidationStatus.Completed) {
                completed++;
                responseSum += uint256(r.response);
                responseCount++;
            }
            else if (r.status == ValidationStatus.Rejected) {
                rejected++;
                responseSum += uint256(r.response);
                responseCount++;
            }
            else if (r.status == ValidationStatus.Cancelled) cancelled++;
        }
    }

    /// @notice ERC-8004: Filtered summary with validator scoping and tag filter
    function getSummary(
        uint256 agentId,
        address[] calldata validatorAddresses,
        string calldata filterTag
    ) external view returns (
        uint256 total,
        uint256 pending,
        uint256 completed,
        uint256 rejected,
        uint256 cancelled,
        uint256 responseSum,
        uint256 responseCount
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        bytes32[] storage ids = _requestsByAgent[agentId];
        bool filterValidators = validatorAddresses.length > 0;
        bool filterT = bytes(filterTag).length > 0;

        for (uint256 i = 0; i < ids.length; i++) {
            ValidationRequest storage r = _requests[ids[i]];

            // Validator filter
            if (filterValidators) {
                bool found = false;
                for (uint256 j = 0; j < validatorAddresses.length; j++) {
                    if (r.validator == validatorAddresses[j]) { found = true; break; }
                }
                if (!found) continue;
            }
            // Tag filter
            if (filterT && keccak256(bytes(r.tag)) != keccak256(bytes(filterTag))) continue;

            total++;
            if (r.status == ValidationStatus.Pending) pending++;
            else if (r.status == ValidationStatus.Completed) {
                completed++;
                responseSum += uint256(r.response);
                responseCount++;
            }
            else if (r.status == ValidationStatus.Rejected) {
                rejected++;
                responseSum += uint256(r.response);
                responseCount++;
            }
            else if (r.status == ValidationStatus.Cancelled) cancelled++;
        }
    }
}
