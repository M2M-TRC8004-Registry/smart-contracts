// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEnhancedIdentityRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function agentWalletOf(uint256 tokenId) external view returns (address);
    function exists(uint256 tokenId) external view returns (bool);
}

/**
 * @title ReputationRegistry
 * @notice Feedback and reputation system for M2M TRC-8004 AI agents
 * 
 * Key improvements:
 * - SECURITY: Only agent owner/wallet can respond to feedback
 * - Agent existence validated on all operations
 * - Simplified sentiment system (Positive/Neutral/Negative)
 * - Thread-based responses per feedback
 */
contract ReputationRegistry {
    enum Sentiment { Neutral, Positive, Negative }

    struct Feedback {
        address client;
        uint256 agentId;
        string feedbackText;
        Sentiment sentiment;
        uint256 timestamp;
        bool revoked;

        // Agent response thread
        string[] responses;
        uint256[] responseTimestamps;
    }

    IEnhancedIdentityRegistry public immutable identityRegistry;

    mapping(uint256 => Feedback[]) private _feedbackByAgent;
    mapping(uint256 => mapping(address => uint256)) public feedbackCountByClient;

    event FeedbackGiven(uint256 indexed agentId, address indexed client, uint256 indexed feedbackIndex, Sentiment sentiment);
    event FeedbackRevoked(uint256 indexed agentId, uint256 indexed feedbackIndex);
    event ResponseAppended(uint256 indexed agentId, uint256 indexed feedbackIndex, address indexed responder);

    constructor(address identityRegistryAddress) {
        require(identityRegistryAddress != address(0), "Zero identity registry");
        identityRegistry = IEnhancedIdentityRegistry(identityRegistryAddress);
    }

    function giveFeedback(
        uint256 agentId,
        string calldata feedbackText,
        Sentiment sentiment
    ) external returns (uint256 feedbackIndex) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        Feedback memory fb;
        fb.client = msg.sender;
        fb.agentId = agentId;
        fb.feedbackText = feedbackText;
        fb.sentiment = sentiment;
        fb.timestamp = block.timestamp;
        fb.revoked = false;

        _feedbackByAgent[agentId].push(fb);
        feedbackIndex = _feedbackByAgent[agentId].length - 1;

        feedbackCountByClient[agentId][msg.sender] += 1;

        emit FeedbackGiven(agentId, msg.sender, feedbackIndex, sentiment);
    }

    function revokeFeedback(uint256 agentId, uint256 feedbackIndex) external {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        require(fb.client == msg.sender, "Not feedback author");
        require(!fb.revoked, "Already revoked");

        fb.revoked = true;
        emit FeedbackRevoked(agentId, feedbackIndex);
    }

    /// @notice SECURITY: Only agent owner or delegated wallet can respond
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

        fb.responses.push(responseText);
        fb.responseTimestamps.push(block.timestamp);

        emit ResponseAppended(agentId, feedbackIndex, msg.sender);
    }

    // --- Views ---

    function getFeedbackCount(uint256 agentId) external view returns (uint256) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        return _feedbackByAgent[agentId].length;
    }

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
        return (fb.client, fb.feedbackText, fb.sentiment, fb.timestamp, fb.revoked, fb.responses.length);
    }

    function getFeedbackResponses(uint256 agentId, uint256 feedbackIndex) external view returns (
        string[] memory responses,
        uint256[] memory responseTimestamps
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(feedbackIndex < _feedbackByAgent[agentId].length, "Bad index");

        Feedback storage fb = _feedbackByAgent[agentId][feedbackIndex];
        return (fb.responses, fb.responseTimestamps);
    }

    function getSummary(uint256 agentId) external view returns (
        uint256 total,
        uint256 active,
        uint256 revoked,
        uint256 positive,
        uint256 neutral,
        uint256 negative
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
        }
    }
}
