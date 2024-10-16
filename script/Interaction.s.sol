// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {IVRFSubscriptionV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
//就是给了一个能看最新的部署的Raffle合约的功能
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script, CodeConstants {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        (uint256 subId,) = createSubscription(vrfCoordinator, helperConfig.getConfig().account);
        return (subId, vrfCoordinator);
    }

    function createSubscription(address vrfCoordinator, address account) public returns (uint256, address) {
        console.log("creating subscription on chain id", block.chainid);
        // //这里也是同理
        // vm.startBroadcast(account);
        // uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        // vm.stopBroadcast();
        uint256 subId;
        if (block.chainid == LOCAL_CHAIN_ID) {
            //这里也是同理
            vm.startBroadcast();
            subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);
            subId = IVRFSubscriptionV2Plus(vrfCoordinator).createSubscription();
            vm.stopBroadcast();
        }

        console.log("Subscription id is", subId);
        console.log("update your config");
        return (subId, vrfCoordinator);
    }

    function run() public {
        createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script, CodeConstants {
    uint256 public constant FUND_AMOUNT = 1e19 + 1e9; //就是对应于LINK

    function run() public {
        fundSubscriptionUsingConfig();
    }

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().link;
        fundSubscription(vrfCoordinator, subscriptionId, linkToken, helperConfig.getConfig().account);
    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address linkToken, address account)
        public
    {
        console.log("Funding subscription", subscriptionId);
        console.log("Using vrfCoordinator", vrfCoordinator);
        console.log("On ChainId", block.chainid);
        //在本地链,用的是mock,所以不需要LINK
        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT);
            vm.stopBroadcast();
            /*在实际sepolia链上,用的是真实的LINK,所以需要LINK
         *
         */
        } else {
            vm.startBroadcast(account);
            /**
             * 会调用vrfCoordinator转LinkToken类型的资金,并附带了subscriptionId信息
             * 因为LINK是erc677协议的代币,所以写了对应的逻辑,需要传以下的内容
             */
            LinkToken(linkToken).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }
    }
}

contract AddConsumer is Script, CodeConstants {
    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(mostRecentlyDeployed);
    }

    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        addConsumer(mostRecentlyDeployed, vrfCoordinator, subId, helperConfig.getConfig().account);
    }

    function addConsumer(address contractToAddtoVrf, address vrfCoordinator, uint256 subId, address account) public {
        console.log("Adding consumer contract", contractToAddtoVrf);
        console.log("To vrfCoordinator", vrfCoordinator);
        console.log("On ChainId", block.chainid);
        //这里唯一能想到的解释就是因为用的是同样的interface,所以会根据vrfCoordinator的不同来调用不同的网络
        // vm.startBroadcast(account);
        // VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subId, contractToAddtoVrf);
        // vm.stopBroadcast();

        if (block.chainid == LOCAL_CHAIN_ID) {
            //这里也是同理
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subId, contractToAddtoVrf);
            vm.stopBroadcast();
        } else {
            //需要用这个账户去发送这个
            vm.startBroadcast(account);
            IVRFSubscriptionV2Plus(vrfCoordinator).addConsumer(subId, contractToAddtoVrf);
            vm.stopBroadcast();
        }
    }
}
