// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEnhancedIdentityRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function agentWalletOf(uint256 tokenId) external view returns (address);
    function exists(uint256 tokenId) external view returns (bool);
}

/**
 * @title ReputationRegistry (TRC-8004 v2)
 * @notice Feedback and reputation system — ERC-8004 compatible superset
 *
 * ERC-8004 Compatibility Additions:
 * - Numeric value (int128 value + uint8 valueDecimals) per feedback
 * - Tags (tag1, tag2), endpoint field
 * - feedbackURI + feedbackHash
 * - responseURI + responseHash per response
 * - readAllFeedback() with filters
 * - getClients(), getLastIndex()
 * - Filtered getSummary(agentId, clients[], tag1, tag2)
 * - getIdentityRegistry() getter
 * - Aligned event signatures (NewFeedback, FeedbackRevoked, ResponseAppended)
 * - Self-feedback prevention (enforced)
 *
 * TRC-8004 Extensions (kept):
 * - feedbackText (on-chain, permanent)
 * - responseText (on-chain, permanent)
 * - Sentiment enum (alongside numeric value)
 * - feedbackCountByClient (Sybil signal)
 * - getFeedbackResponses() (on-chain conversation)
 * - Unfiltered getSummary(agentId)
 */
contract ReputationRegistry {
    // --- String length limits (security hardening) ---
    uint256 public constant MAX_URI_LENGTH = 2048;
    uint256 public constant MAX_TEXT_LENGTH = 2048;
    uint256 public constant MAX_TAG_LENGTH = 128;
    uint256 public constant MAX_ENDPOINT_LENGTH = 512;
    uint256 public constant MAX_RESPONSES_PER_FEEDBACK = 30;

    enum Sentiment { Neutral, Positive, Negative }

    struct Feedback {
        address client;
        uint256 agentId;
        // TRC-8004 extension: on-chain text
        string feedbackText;
        Sentiment sentiment;
        // ERC-8004 compat: numeric value
        int128 value;
        uint8 valueDecimals;
        // ERC-8004 compat: tags and endpoint
        string tag1;
        string tag2;
        string endpoint;
        // ERC-8004 compat: off-chain reference
        string feedbackURI;
        bytes32 feedbackHash;
        // Timestamps
        uint256 timestamp;
        bool revoked;
        // Agent response thread
        string[] responseTexts;           // TRC-8004: on-chain
        string[] responseURIs;            // ERC-8004: off-chain
        bytes32[] responseHashes;         // ERC-8004: integrity
        uint256[] responseTimestamps;
    }

    IEnhancedIdentityRegistry public immutable identityRegistry;

    mapping(uint256 => Feedback[]) private _feedbackByAgent;
    mapping(uint256 => mapping(address => uint256)) public feedbackCountByClient;
    mapping(uint256 => address[]) private _clientsByAgent;
    mapping(uint256 => mapping(address => bool)) private _isClientTracked;

    /// @notice ERC-8004 aligned: NewFeedback — core fields
    event NewFeedback(
        uint256 indexed agentId,
        address indexed client,
        uint256 indexed feedbackIndex,
        Sentiment sentiment,
        int128 value,
        uint8 valueDecimals
    );

    /// @notice ERC-8004 extended: tags, endpoint, URI, hash (emitted alongside NewFeedback)
    event NewFeedbackDetail(
        uint256 indexed agentId,
        uint256 indexed feedbackIndex,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );

    /// @notice TRC-8004 legacy event (kept for backward compat)
    event FeedbackGiven(uint256 indexed agentId, address indexed client, uint256 indexed feedbackIndex, Sentiment sentiment);

    /// @notice ERC-8004 aligned: includes client address
    event FeedbackRevoked(uint256 indexed agentId, uint256 indexed feedbackIndex, address indexed clientAddress);

    /// @notice ERC-8004 aligned: includes client, URI, hash
    event ResponseAppended(
        uint256 indexed agentId,
        uint256 indexed feedbackIndex,
        address indexed responder,
        address clientAddress,
        string responseURI,
        bytes32 responseHash
    );

    constructor(address identityRegistryAddress) {
        require(identityRegistryAddress != address(0), "Zero identity registry");
        identityRegistry = IEnhancedIdentityRegistry(identityRegistryAddress);
    }

    /// @notice ERC-8004 getter for linked registry
    function getIdentityRegistry() external view returns (address) {
        return address(identityRegistry);
    }

    /// @notice Input struct for full giveFeedback (avoids stack-too-deep)
    struct FeedbackInput {
        uint256 agentId;
        string feedbackText;
        Sentiment sentiment;
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        string endpoint;
        string feedbackURI;
        bytes32 feedbackHash;
    }

    /// @dev Internal self-feedback prevention check
    function _checkNotSelfFeedback(uint256 agentId) internal view {
        require(msg.sender != identityRegistry.ownerOf(agentId), "Self-feedback not allowed");
        address agentWallet = identityRegistry.agentWalletOf(agentId);
        require(agentWallet == address(0) || msg.sender != agentWallet, "Self-feedback not allowed");
    }

    /// @dev Internal string length validation
    function _validateInputStrings(FeedbackInput calldata input) internal pure {
        require(bytes(input.feedbackText).length <= MAX_TEXT_LENGTH, "Text too long");
        require(bytes(input.tag1).length <= MAX_TAG_LENGTH, "Tag1 too long");
        require(bytes(input.tag2).length <= MAX_TAG_LENGTH, "Tag2 too long");
        require(bytes(input.endpoint).length <= MAX_ENDPOINT_LENGTH, "Endpoint too long");
        require(bytes(input.feedbackURI).length <= MAX_URI_LENGTH, "URI too long");
    }

    /// @notice Full giveFeedback — TRC-8004 extension fields + ERC-8004 compat fields
    function giveFeedback(FeedbackInput calldata input) external returns (uint256 feedbackIndex) {
        require(identityRegistry.exists(input.agentId), "Nonexistent agent");
        _checkNotSelfFeedback(input.agentId);
        _validateInputStrings(input);

        feedbackIndex = _storeFeedback(input);
        _emitFeedbackEvents(input.agentId, feedbackIndex);
    }

    /// @notice TRC-8004 legacy: simple giveFeedback (backward compat)
    function giveFeedback(
        uint256 agentId,
        string calldata feedbackText,
        Sentiment sentiment
    ) external returns (uint256 feedbackIndex) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        _checkNotSelfFeedback(agentId);
        require(bytes(feedbackText).length <= MAX_TEXT_LENGTH, "Text too long");

        feedbackIndex = _storeLegacyFeedback(agentId, feedbackText, sentiment);
        _emitFeedbackEvents(agentId, feedbackIndex);
    }

    /// @dev Push full feedback to storage from FeedbackInput struct
    function _storeFeedback(FeedbackInput calldata input) internal returns (uint256 feedbackIndex) {
        Feedback[] storage arr = _feedbackByAgent[input.agentId];
        arr.push(); // push empty, then set fields to avoid memory struct
        feedbackIndex = arr.length - 1;
        Feedback storage fb = arr[feedbackIndex];

        fb.client = msg.sender;
        fb.agentId = input.agentId;
        fb.feedbackText = input.feedbackText;
        fb.sentiment = input.sentiment;
        fb.value = input.value;
        fb.valueDecimals = input.valueDecimals;
        fb.tag1 = input.tag1;
        fb.tag2 = input.tag2;
        fb.endpoint = input.endpoint;
        fb.feedbackURI = input.feedbackURI;
        fb.feedbackHash = input.feedbackHash;
        fb.timestamp = block.timestamp;

        _trackClient(input.agentId);
    }

    /// @dev Push legacy (simple) feedback to storage
    function _storeLegacyFeedback(
        uint256 agentId,
        string calldata feedbackText,
        Sentiment sentiment
    ) internal returns (uint256 feedbackIndex) {
        Feedback[] storage arr = _feedbackByAgent[agentId];
        arr.push();
        feedbackIndex = arr.length - 1;
        Feedback storage fb = arr[feedbackIndex];

        fb.client = msg.sender;
        fb.agentId = agentId;
        fb.feedbackText = feedbackText;
        fb.sentiment = sentiment;
        fb.timestamp = block.timestamp;

        _trackClient(agentId);
    }

    /// @dev Track client address and count
    function _trackClient(uint256 agentId) internal {
        feedbackCountByClient[agentId][msg.sender] += 1;
        if (!_isClientTracked[agentId][msg.sender]) {
            _clientsByAgent[agentId].push(msg.sender);
            _isClientTracked[agentId][msg.sender] = true;
        }
    }

    /// @dev Emit all feedback events from storage (separate frame to avoid stack pressure)
    function _emitFeedbackEvents(uint256 agentId, uint256 feedbackIndex) internal {
        Feedback storage stored = _feedbackByAgent[agentId][feedbackIndex];
        emit NewFeedback(
            agentId, msg.sender, feedbackIndex, stored.sentiment,
            stored.value, stored.valueDecimals
        );
        emit NewFeedbackDetail(
            agentId, feedbackIndex,
            stored.tag1, stored.tag2, stored.endpoint,
            stored.feedbackURI, stored.feedbackHash
        );
        emit FeedbackGiven(agentId, msg.sender, feedbackIndex, stored.sentiment);
    }

    function revokeFeedback(uint256 agentId, uint256 feedbackIndex) external {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        require(fb.client == msg.sender, "Not feedback author");
        require(!fb.revoked, "Already revoked");

        fb.revoked = true;
        emit FeedbackRevoked(agentId, feedbackIndex, msg.sender);
    }

    /// @notice Full appendResponse — TRC-8004 on-chain text + ERC-8004 URI/hash
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint256 feedbackIndex,
        string calldata responseText,
        string calldata responseURI,
        bytes32 responseHash
    ) external {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        address owner = identityRegistry.ownerOf(agentId);
        address agentWallet = identityRegistry.agentWalletOf(agentId);

        require(
            msg.sender == owner || (agentWallet != address(0) && msg.sender == agentWallet),
            "Not agent authority"
        );

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        require(!fb.revoked, "Feedback revoked");
        require(fb.client == clientAddress, "Client mismatch");
        require(fb.responseTexts.length < MAX_RESPONSES_PER_FEEDBACK, "Max responses reached");
        require(bytes(responseText).length <= MAX_TEXT_LENGTH, "Text too long");
        require(bytes(responseURI).length <= MAX_URI_LENGTH, "URI too long");

        fb.responseTexts.push(responseText);
        fb.responseURIs.push(responseURI);
        fb.responseHashes.push(responseHash);
        fb.responseTimestamps.push(block.timestamp);

        emit ResponseAppended(agentId, feedbackIndex, msg.sender, clientAddress, responseURI, responseHash);
    }

    /// @notice TRC-8004 legacy: simple appendResponse (backward compat)
    function appendResponse(
        uint256 agentId,
        uint256 feedbackIndex,
        string calldata responseText
    ) external {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        address owner = identityRegistry.ownerOf(agentId);
        address agentWallet = identityRegistry.agentWalletOf(agentId);

        require(
            msg.sender == owner || (agentWallet != address(0) && msg.sender == agentWallet),
            "Not agent authority"
        );

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        require(!fb.revoked, "Feedback revoked");
        require(fb.responseTexts.length < MAX_RESPONSES_PER_FEEDBACK, "Max responses reached");
        require(bytes(responseText).length <= MAX_TEXT_LENGTH, "Text too long");

        fb.responseTexts.push(responseText);
        fb.responseURIs.push("");
        fb.responseHashes.push(bytes32(0));
        fb.responseTimestamps.push(block.timestamp);

        emit ResponseAppended(agentId, feedbackIndex, msg.sender, fb.client, "", bytes32(0));
    }

    // --- Views ---

    function getFeedbackCount(uint256 agentId) external view returns (uint256) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        return _feedbackByAgent[agentId].length;
    }

    /// @notice Get core feedback fields (split to avoid stack-too-deep)
    function getFeedback(uint256 agentId, uint256 feedbackIndex) external view returns (
        address client,
        string memory feedbackText,
        Sentiment sentiment,
        uint256 timestamp,
        bool revoked,
        uint256 responseCount
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        return (
            fb.client, fb.feedbackText, fb.sentiment,
            fb.timestamp, fb.revoked,
            fb.responseTexts.length
        );
    }

    /// @notice Get extended feedback fields: value, tags, URI (split to avoid stack-too-deep)
    function getFeedbackExtended(uint256 agentId, uint256 feedbackIndex) external view returns (
        int128 value,
        uint8 valueDecimals,
        string memory tag1,
        string memory tag2,
        string memory endpoint,
        string memory feedbackURI,
        bytes32 feedbackHash
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        return (
            fb.value, fb.valueDecimals,
            fb.tag1, fb.tag2, fb.endpoint,
            fb.feedbackURI, fb.feedbackHash
        );
    }

    /// @notice TRC-8004 extension: on-chain response thread
    function getFeedbackResponses(uint256 agentId, uint256 feedbackIndex) external view returns (
        string[] memory responseTexts,
        string[] memory responseURIs,
        bytes32[] memory responseHashes,
        uint256[] memory responseTimestamps
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        return (fb.responseTexts, fb.responseURIs, fb.responseHashes, fb.responseTimestamps);
    }

    /// @notice ERC-8004: List all addresses that have given feedback
    function getClients(uint256 agentId) external view returns (address[] memory) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        return _clientsByAgent[agentId];
    }

    /// @notice ERC-8004: Per-client feedback index
    function getLastIndex(uint256 agentId, address client) external view returns (uint256) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        return feedbackCountByClient[agentId][client];
    }

    /// @notice TRC-8004: Unfiltered summary — returns sentiment counts + value aggregates
    function getSummary(uint256 agentId) external view returns (
        uint256 total,
        uint256 active,
        uint256 revoked,
        uint256 positive,
        uint256 neutral,
        uint256 negative,
        int256 valueSum,
        uint256 valueCount
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        Feedback[] storage arr = _feedbackByAgent[agentId];
        total = arr.length;

        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i].revoked) {
                revoked += 1;
                continue;
            }
            active += 1;
            if (arr[i].sentiment == Sentiment.Positive) positive += 1;
            else if (arr[i].sentiment == Sentiment.Negative) negative += 1;
            else neutral += 1;

            if (arr[i].value != 0 || arr[i].valueDecimals != 0) {
                valueSum += int256(arr[i].value);
                valueCount += 1;
            }
        }
    }

    /// @notice ERC-8004: Filtered summary with client scoping and tag filters
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata filterTag1,
        string calldata filterTag2
    ) external view returns (
        uint256 total,
        uint256 active,
        uint256 revoked,
        uint256 positive,
        uint256 neutral,
        uint256 negative,
        int256 valueSum,
        uint256 valueCount
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        Feedback[] storage arr = _feedbackByAgent[agentId];
        bool filterClients = clientAddresses.length > 0;
        bool filterT1 = bytes(filterTag1).length > 0;
        bool filterT2 = bytes(filterTag2).length > 0;

        for (uint256 i = 0; i < arr.length; i++) {
            // Client filter
            if (filterClients) {
                bool found = false;
                for (uint256 j = 0; j < clientAddresses.length; j++) {
                    if (arr[i].client == clientAddresses[j]) { found = true; break; }
                }
                if (!found) continue;
            }
            // Tag filters
            if (filterT1 && keccak256(bytes(arr[i].tag1)) != keccak256(bytes(filterTag1))) continue;
            if (filterT2 && keccak256(bytes(arr[i].tag2)) != keccak256(bytes(filterTag2))) continue;

            total += 1;
            if (arr[i].revoked) {
                revoked += 1;
                continue;
            }
            active += 1;
            if (arr[i].sentiment == Sentiment.Positive) positive += 1;
            else if (arr[i].sentiment == Sentiment.Negative) negative += 1;
            else neutral += 1;

            if (arr[i].value != 0 || arr[i].valueDecimals != 0) {
                valueSum += int256(arr[i].value);
                valueCount += 1;
            }
        }
    }

    /// @notice ERC-8004: Bulk filtered feedback read
    function readAllFeedback(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata filterTag1,
        string calldata filterTag2,
        bool includeRevoked
    ) external view returns (uint256[] memory indices) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        Feedback[] storage arr = _feedbackByAgent[agentId];
        bool filterClients = clientAddresses.length > 0;
        bool filterT1 = bytes(filterTag1).length > 0;
        bool filterT2 = bytes(filterTag2).length > 0;

        // First pass: count matches
        uint256 matchCount = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            if (!includeRevoked && arr[i].revoked) continue;
            if (filterClients) {
                bool found = false;
                for (uint256 j = 0; j < clientAddresses.length; j++) {
                    if (arr[i].client == clientAddresses[j]) { found = true; break; }
                }
                if (!found) continue;
            }
            if (filterT1 && keccak256(bytes(arr[i].tag1)) != keccak256(bytes(filterTag1))) continue;
            if (filterT2 && keccak256(bytes(arr[i].tag2)) != keccak256(bytes(filterTag2))) continue;
            matchCount++;
        }

        // Second pass: collect indices
        indices = new uint256[](matchCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            if (!includeRevoked && arr[i].revoked) continue;
            if (filterClients) {
                bool found = false;
                for (uint256 j = 0; j < clientAddresses.length; j++) {
                    if (arr[i].client == clientAddresses[j]) { found = true; break; }
                }
                if (!found) continue;
            }
            if (filterT1 && keccak256(bytes(arr[i].tag1)) != keccak256(bytes(filterTag1))) continue;
            if (filterT2 && keccak256(bytes(arr[i].tag2)) != keccak256(bytes(filterTag2))) continue;
            indices[idx++] = i;
        }
    }
}
