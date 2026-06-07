// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/DAO.sol";

contract DAOTest is Test {
    DAO dao;
    address admin;
    address member1;
    address member2;
    address member3;
    address nonMember;

    uint256 constant QUORUM = 51;
    uint256 constant VOTING_DURATION = 1 days;

    function setUp() public {
        admin = address(this);
        member1 = address(0x1111);
        member2 = address(0x2222);
        member3 = address(0x3333);
        nonMember = address(0x4444);
        dao = new DAO(QUORUM, VOTING_DURATION);
        dao.addMember(member1);
        dao.addMember(member2);
        dao.addMember(member3);
        vm.deal(address(dao), 10 ether);
    }

    function testInitialState() public view {
        assertEq(dao.admin(), admin);
        assertEq(dao.quorumPercentage(), QUORUM);
        assertEq(dao.votingDuration(), VOTING_DURATION);
        assertEq(dao.memberCount(), 4);
        assertTrue(dao.members(admin));
    }

    function testAddMember() public {
        address newMember = address(0x5555);
        dao.addMember(newMember);
        assertTrue(dao.members(newMember));
        assertEq(dao.memberCount(), 5);
    }

    function testRemoveMember() public {
        dao.removeMember(member3);
        assertFalse(dao.members(member3));
        assertEq(dao.memberCount(), 3);
    }

    function testCannotRemoveAdmin() public {
        vm.expectRevert("Cannot remove admin");
        dao.removeMember(admin);
    }

    function testOnlyMemberCanPropose() public {
        vm.prank(nonMember);
        vm.expectRevert("Only members");
        dao.createProposal("Test", "Description", address(0), "", 0);
    }

    function testCreateProposal() public {
        vm.prank(member1);
        uint256 id = dao.createProposal("Test Proposal", "Description", address(0), "", 0);
        assertEq(id, 0);
        assertEq(dao.proposalCount(), 1);
    }

    function testVote() public {
        vm.prank(member1);
        dao.createProposal("Test", "Description", address(0), "", 0);
        vm.prank(member1);
        dao.vote(0, true);
        (,,, uint256 votesFor,,,, ) = dao.getProposal(0);
        assertEq(votesFor, 1);
    }

    function testCannotVoteTwice() public {
        vm.prank(member1);
        dao.createProposal("Test", "Description", address(0), "", 0);
        vm.prank(member1);
        dao.vote(0, true);
        vm.prank(member1);
        vm.expectRevert("Already voted");
        dao.vote(0, true);
    }

    function testFinalizeProposalPassed() public {
        vm.prank(member1);
        dao.createProposal("Test", "Description", address(0), "", 0);
        vm.prank(admin);
        dao.vote(0, true);
        vm.prank(member1);
        dao.vote(0, true);
        vm.prank(member2);
        dao.vote(0, true);
        vm.warp(block.timestamp + 2 days);
        dao.finalizeProposal(0);
        (,,,,,, DAO.ProposalStatus status,) = dao.getProposal(0);
        assertEq(uint256(status), uint256(DAO.ProposalStatus.Passed));
    }

    function testFinalizeProposalRejectedByQuorum() public {
        vm.prank(member1);
        dao.createProposal("Test", "Description", address(0), "", 0);
        vm.prank(member1);
        dao.vote(0, true);
        vm.warp(block.timestamp + 2 days);
        dao.finalizeProposal(0);
        (,,,,,, DAO.ProposalStatus status,) = dao.getProposal(0);
        assertEq(uint256(status), uint256(DAO.ProposalStatus.Rejected));
    }

    function testCancelProposal() public {
        vm.prank(member1);
        dao.createProposal("Test", "Description", address(0), "", 0);
        vm.prank(member1);
        dao.cancelProposal(0);
        (,,,,,, DAO.ProposalStatus status,) = dao.getProposal(0);
        assertEq(uint256(status), uint256(DAO.ProposalStatus.Cancelled));
    }

    function testOnlyNonMemberCannotVote() public {
        vm.prank(member1);
        dao.createProposal("Test", "Description", address(0), "", 0);
        vm.prank(nonMember);
        vm.expectRevert("Only members");
        dao.vote(0, true);
    }

    function testProposalCreatedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit DAO.ProposalCreated(0, member1, "Test Proposal");
        vm.prank(member1);
        dao.createProposal("Test Proposal", "Description", address(0), "", 0);
    }

    function testMemberAddedEvent() public {
        address newMember = address(0x5555);
        vm.expectEmit(true, true, true, true);
        emit DAO.MemberAdded(newMember);
        dao.addMember(newMember);
    }

    receive() external payable {}
}
