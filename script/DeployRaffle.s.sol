// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interaction.s.sol";

contract DeployRaffle is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        //配置好了本地网络
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            //应该创建订阅
            CreateSubscription createSubscription = new CreateSubscription();
            //在这里出现了分流,sepolia链的是sepolia链的设置,本地链是本地链的设置
            (config.subscriptionId, config.vrfCoordinator) =
                createSubscription.createSubscription(config.vrfCoordinator, config.account);

            FundSubscription fundSubscription = new FundSubscription();
            //这里也正常,调用不同链的设置
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }

        //根据不同的用户配置部署的合约
        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        //写在这里是因为要用raffle的合约地址
        //根据不同的配置实现addConsumer
        AddConsumer addconsumer = new AddConsumer();
        addconsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);
        //这里返回了,就可以去test里面用了
        return (raffle, helperConfig);
    }
}
