// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    Raffle public raffle;
    HelperConfig public helperConfig;

    address public PLAYER = makeAddr("player");

    uint256 constant STARTING_PALYER_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        vm.deal(PLAYER, STARTING_PALYER_BALANCE);
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;
    }

    function testRaffleInitializesInOpenState() public view {
        assert(uint256(raffle.getRaffleState()) == 0);
    }

    function testRaffleRevertsWhenYouDontpayEnough() public {
        vm.startPrank(PLAYER);
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
        vm.stopPrank();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.startPrank(PLAYER);
        //是raffle合约发出去的
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //让当前的block时间超过interval
        vm.warp(block.timestamp + interval + 1);
        //让区块也+1了
        vm.roll(block.number + 1);
        vm.stopPrank();
        raffle.performUpkeep("");

        vm.startPrank(PLAYER);
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();
    }

    /**
     * CHECK UPKEEP***********************
     */
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        /**
         * 没有enterRaffle
         */
        //让当前的block时间超过interval
        vm.warp(block.timestamp + interval + 1);
        //让区块也+1了
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    //检查raffle关闭的情况下还可以抽奖吗
    function testCheckUpkeepReturnFalseIfRaffleIsntOpen() public {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //让当前的block时间超过interval
        vm.warp(block.timestamp + interval + 1);
        //让区块也+1了
        vm.roll(block.number + 1);
        vm.stopPrank();
        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnFalseIfNotEnoughTimeHasPassed() public {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //让当前的block时间超过interval
        vm.warp(block.timestamp + interval - 1);
        vm.stopPrank();
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testEntranceFeeisUpIfItRcord() public view {
        assert(entranceFee == raffle.getEntranceFee());
    }

    function testGetRandomNum() public {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //让当前的block时间超过interval
        vm.warp(block.timestamp + interval + 1);
        //让区块也+1了
        vm.roll(block.number + 1);
        vm.stopPrank();
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //让当前的block时间超过interval
        vm.warp(block.timestamp + interval + 1);
        //让区块也+1了
        vm.roll(block.number + 1);
        vm.stopPrank();
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        //从现在开始记录所有的发出的log
        vm.recordLogs();
        raffle.performUpkeep("");
        //将记录的所有log放到这个数组中
        Vm.Log[] memory entries = vm.getRecordedLogs();
        //因为vrf会先发出,所以这样取到的是我们自己的
        //后面的topics因为第一个经常用来保存的是额外的东西
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /**
     * FULFILLRANDOMWORDS*********************************
     */
    //这里用了模糊测试,foundry实际用了不同的数量
    function testFulfillrandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEntered
        skipFork
    {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillrandomWordsPicksAWinnerResetAndSendsMoney() public raffleEntered skipFork {
        //总共四个人进入
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectWinner = address(1);
        //添加了三个抽奖的用户
        for (uint256 i = startingIndex; i < additionalEntrants + startingIndex; i++) {
            address newPlayer = address(uint160(i));
            //不仅给了钱,还修改了下一个交易的发送对象为自身
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        /**
         * 接下来就是手动调用mock合约的fullfillrandomwords,因为这不是真实网络
         * 所以需要手动调用,但是他会根据consumer合约来自动回调
         *
         */
        // vm.deal(vrfCoordinator, 10 ether);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState rafflestate = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectWinner);
        assert(rafflestate == Raffle.RaffleState.OPEN);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
