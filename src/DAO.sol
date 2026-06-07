// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract DAO {
    address public admin;
    uint256 public proposalCount;
    uint256 public quorumPercentage;
    uint256 public votingDuration;
    uint256 public memberCount;

    enum ProposalStatus { Active, Passed, Rejected, Executed, Cancelled }

    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        address target;
        bytes callData;
        uint256 value;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 deadline;
        ProposalStatus status;
        bool executed;
    }

    mapping(address => bool) public members;
    mapping(address => uint256) public memberJoinedAt;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event ProposalCreated(uint256 indexed id, address indexed proposer, string title);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCancelled(uint256 indexed id);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyMember() {
        require(members[msg.sender], "Only members");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposalId < proposalCount, "Proposal does not exist");
        _;
    }

    constructor(uint256 _quorumPercentage, uint256 _votingDuration) {
        require(_quorumPercentage > 0 && _quorumPercentage <= 100, "Invalid quorum");
        admin = msg.sender;
        quorumPercentage = _quorumPercentage;
        votingDuration = _votingDuration;
        members[msg.sender] = true;
        memberJoinedAt[msg.sender] = block.timestamp;
        memberCount = 1;
    }

    receive() external payable {}

    function addMember(address member) public onlyAdmin {
        require(member != address(0), "Invalid address");
        require(!members[member], "Already a member");
        members[member] = true;
        memberJoinedAt[member] = block.timestamp;
        memberCount++;
        emit MemberAdded(member);
    }

    function removeMember(address member) public onlyAdmin {
        require(members[member], "Not a member");
        require(member != admin, "Cannot remove admin");
        members[member] = false;
        memberCount--;
        emit MemberRemoved(member);
    }

    function createProposal(
        string memory title,
        string memory description,
        address target,
        bytes memory callData,
        uint256 value
    ) public onlyMember returns (uint256) {
        require(bytes(title).length > 0, "Title cannot be empty");

        uint256 proposalId = proposalCount;
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            target: target,
            callData: callData,
            value: value,
            votesFor: 0,
            votesAgainst: 0,
            deadline: block.timestamp + votingDuration,
            status: ProposalStatus.Active,
            executed: false
        });

        proposalCount++;
        emit ProposalCreated(proposalId, msg.sender, title);
        return proposalId;
    }

    function vote(uint256 proposalId, bool support) public onlyMember proposalExists(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp < proposal.deadline, "Voting ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }

        emit VoteCast(proposalId, msg.sender, support);
    }

    function finalizeProposal(uint256 proposalId) public proposalExists(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Already finalized");
        require(block.timestamp >= proposal.deadline, "Voting not ended");

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 quorumRequired = (memberCount * quorumPercentage) / 100;

        if (totalVotes < quorumRequired) {
            proposal.status = ProposalStatus.Rejected;
            return;
        }

        if (proposal.votesFor > proposal.votesAgainst) {
            proposal.status = ProposalStatus.Passed;
        } else {
            proposal.status = ProposalStatus.Rejected;
        }
    }

    function executeProposal(uint256 proposalId) public onlyAdmin proposalExists(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Passed, "Proposal not passed");
        require(!proposal.executed, "Already executed");
        require(address(this).balance >= proposal.value, "Insufficient balance");

        proposal.executed = true;
        proposal.status = ProposalStatus.Executed;

        if (proposal.target != address(0)) {
            (bool success,) = proposal.target.call{value: proposal.value}(proposal.callData);
            require(success, "Execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId) public proposalExists(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Cannot cancel");
        require(msg.sender == proposal.proposer || msg.sender == admin, "Not authorized");

        proposal.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    function getProposal(uint256 proposalId) public view proposalExists(proposalId)
        returns (uint256, address, string memory, uint256, uint256, uint256, ProposalStatus, bool)
    {
        Proposal memory p = proposals[proposalId];
        return (p.id, p.proposer, p.title, p.votesFor, p.votesAgainst, p.deadline, p.status, p.executed);
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
