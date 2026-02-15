// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEnhancedIdentityRegistry {
    function exists(uint256 tokenId) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
    function agentWalletOf(uint256 tokenId) external view returns (address);
}

/**
 * @title IncidentRegistry (TRC-8004 Extension)
 * @notice On-chain incident reporting for AI agent failures, disputes, or malicious behavior
 *
 * Not part of ERC-8004 spec — proposed by SumeetChougule on Ethereum Magicians.
 * TRC-8004 is the first implementation.
 *
 * Features:
 * - reportIncident: Anyone can report an incident against an agent
 * - respondToIncident: Agent owner/wallet can respond
 * - resolveIncident: Reporter can mark as resolved
 * - getIncidents: List all incidents for an agent
 */
contract IncidentRegistry {
    // --- String length limits (security hardening) ---
    uint256 public constant MAX_URI_LENGTH = 2048;
    uint256 public constant MAX_CATEGORY_LENGTH = 128;

    enum IncidentStatus { Open, Responded, Resolved }
    enum Resolution { None, Acknowledged, Disputed, Fixed, NotABug, Duplicate }

    struct Incident {
        uint256 incidentId;
        uint256 agentId;
        address reporter;
        string incidentURI;
        bytes32 incidentHash;
        string category;          // "failure", "dispute", "malicious", "other"
        IncidentStatus status;
        uint256 reportedAt;
        // Response
        string responseURI;
        bytes32 responseHash;
        address respondedBy;
        uint256 respondedAt;
        // Resolution
        Resolution resolution;
        uint256 resolvedAt;
    }

    IEnhancedIdentityRegistry public immutable identityRegistry;

    uint256 private _nextIncidentId = 1;
    mapping(uint256 => Incident) private _incidents;
    mapping(uint256 => uint256[]) private _incidentsByAgent;
    mapping(address => uint256[]) private _incidentsByReporter;

    event IncidentReported(
        uint256 indexed incidentId,
        uint256 indexed agentId,
        address indexed reporter,
        string category,
        string incidentURI,
        bytes32 incidentHash
    );

    event IncidentResponded(
        uint256 indexed incidentId,
        uint256 indexed agentId,
        address indexed respondedBy,
        string responseURI,
        bytes32 responseHash
    );

    event IncidentResolved(
        uint256 indexed incidentId,
        uint256 indexed agentId,
        address indexed resolvedBy,
        Resolution resolution
    );

    constructor(address identityRegistryAddress) {
        require(identityRegistryAddress != address(0), "Zero identity registry");
        identityRegistry = IEnhancedIdentityRegistry(identityRegistryAddress);
    }

    function getIdentityRegistry() external view returns (address) {
        return address(identityRegistry);
    }

    function reportIncident(
        uint256 agentId,
        string calldata incidentURI,
        bytes32 incidentHash,
        string calldata category
    ) external returns (uint256 incidentId) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        require(bytes(incidentURI).length <= MAX_URI_LENGTH, "URI too long");
        require(bytes(category).length <= MAX_CATEGORY_LENGTH, "Category too long");

        incidentId = _nextIncidentId++;

        Incident storage inc = _incidents[incidentId];
        inc.incidentId = incidentId;
        inc.agentId = agentId;
        inc.reporter = msg.sender;
        inc.incidentURI = incidentURI;
        inc.incidentHash = incidentHash;
        inc.category = category;
        inc.status = IncidentStatus.Open;
        inc.reportedAt = block.timestamp;

        _incidentsByAgent[agentId].push(incidentId);
        _incidentsByReporter[msg.sender].push(incidentId);

        emit IncidentReported(incidentId, agentId, msg.sender, category, incidentURI, incidentHash);
    }

    function respondToIncident(
        uint256 incidentId,
        string calldata responseURI,
        bytes32 responseHash
    ) external {
        Incident storage inc = _incidents[incidentId];
        require(inc.reportedAt != 0, "Unknown incident");
        require(inc.status == IncidentStatus.Open, "Not open");
        require(bytes(responseURI).length <= MAX_URI_LENGTH, "URI too long");

        address owner = identityRegistry.ownerOf(inc.agentId);
        address agentWallet = identityRegistry.agentWalletOf(inc.agentId);

        require(
            msg.sender == owner || (agentWallet != address(0) && msg.sender == agentWallet),
            "Not agent authority"
        );

        inc.responseURI = responseURI;
        inc.responseHash = responseHash;
        inc.respondedBy = msg.sender;
        inc.respondedAt = block.timestamp;
        inc.status = IncidentStatus.Responded;

        emit IncidentResponded(incidentId, inc.agentId, msg.sender, responseURI, responseHash);
    }

    function resolveIncident(uint256 incidentId, Resolution resolution) external {
        Incident storage inc = _incidents[incidentId];
        require(inc.reportedAt != 0, "Unknown incident");
        require(inc.status == IncidentStatus.Responded, "Must be responded first");
        require(inc.reporter == msg.sender, "Not reporter");

        inc.resolution = resolution;
        inc.resolvedAt = block.timestamp;
        inc.status = IncidentStatus.Resolved;

        emit IncidentResolved(incidentId, inc.agentId, msg.sender, resolution);
    }

    // --- Views ---

    function getIncident(uint256 incidentId) external view returns (Incident memory) {
        Incident memory inc = _incidents[incidentId];
        require(inc.reportedAt != 0, "Unknown incident");
        return inc;
    }

    function getIncidents(uint256 agentId) external view returns (uint256[] memory) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        return _incidentsByAgent[agentId];
    }

    function getReporterIncidents(address reporter) external view returns (uint256[] memory) {
        return _incidentsByReporter[reporter];
    }

    function getIncidentCount(uint256 agentId) external view returns (uint256) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");
        return _incidentsByAgent[agentId].length;
    }

    function getSummary(uint256 agentId) external view returns (
        uint256 total,
        uint256 open,
        uint256 responded,
        uint256 resolved
    ) {
        require(identityRegistry.exists(agentId), "Nonexistent agent");

        uint256[] storage ids = _incidentsByAgent[agentId];
        total = ids.length;

        for (uint256 i = 0; i < ids.length; i++) {
            IncidentStatus st = _incidents[ids[i]].status;
            if (st == IncidentStatus.Open) open++;
            else if (st == IncidentStatus.Responded) responded++;
            else if (st == IncidentStatus.Resolved) resolved++;
        }
    }
}
