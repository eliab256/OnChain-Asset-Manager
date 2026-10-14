// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseIndexFactoryTest} from "./BaseIndexFactory.t.sol";
import {Index} from "../../../src/Index.sol";
import {IndexAsset, IndexDeployParams} from "../../../src/types.sol";
import {
    ConstructorDecimalsRevertingTokenMock
} from "../../mocks/DecimalsTokenMocks.sol";
import {IndexFactory__IndexDeployFailed} from "../../../src/errors/IndexFactoryErrors.sol";
import {Index__ZeroAddress} from "../../../src/errors/IndexErrors.sol";

/**
 * @dev IndexFactory.deployIndex: permissionless CREATE2 deployment with msg.sender as IndexManager,
 *      CREATE2 collisions, Index constructor failures, and the Index zero-IndexManager check.
 */
contract IndexFactoryDeployIndexTest is BaseIndexFactoryTest {
    function setUp() public override {
        super.setUp();
    }

    // =========================================================================
    //  deployIndex — happy path
    // =========================================================================

    function testDeployIndexByArbitraryCallerDeploysAtExpectedAddress() public {
        IndexDeployParams memory params = _defaultParams();
        address expected = _expectedIndexAddress(params, s_attacker, SALT);
        assertEq(expected.code.length, 0, "target must be empty before");

        address index = _deployIndexAs(s_attacker, params, SALT);

        // The CREATE2 address commits to the full initcode: it proves every constructor argument
        // (swapManager, priceFeedManager and universalRouter included, which have no getter) was
        // encoded in the Index order with msg.sender as IndexManager.
        assertEq(index, expected, "CREATE2 address");
        assertGt(index.code.length, 0, "index must have code");
    }

    function testDeployIndexSetsCallerAsIndexManager() public {
        address index = _deployIndexAs(s_attacker, _defaultParams(), SALT);
        assertEq(Index(index).getIndexManager(), s_attacker);
    }

    function testDeployIndexSetsConstructorValues() public {
        IndexDeployParams memory params = _defaultParams();
        Index index = Index(_deployIndexAs(s_attacker, params, SALT));

        assertEq(index.name(), TEST_INDEX_NAME, "name");
        assertEq(index.symbol(), TEST_INDEX_SYMBOL, "symbol");
        assertEq(index.getRouter(), address(router), "router");
        assertEq(index.getUsdc(), address(mockUsdc), "usdc");
        assertEq(index.getAsset0(), address(mockWeth), "asset0");
        assertEq(index.getAsset1(), address(mockLink), "asset1");

        (uint128 weight0, uint128 weight1) = index.getAssetsWeights();
        assertEq(weight0, weight60, "weight0");
        assertEq(weight1, weight40, "weight1");

        (uint32 feePercentage, uint128 totalFees) = index.getFeesInfo();
        assertEq(feePercentage, validFeePercentage, "fee percentage");
        assertEq(totalFees, 0, "no fees yet");

        (uint8 decimals0, uint8 decimals1, uint8 decimalsUsdc) = index
            .getAssetsAndUsdcDecimals();
        assertEq(decimals0, mockWeth.decimals(), "asset0 decimals");
        assertEq(decimals1, mockLink.decimals(), "asset1 decimals");
        assertEq(decimalsUsdc, mockUsdc.decimals(), "usdc decimals");

        assertFalse(index.getInitializationStatus(), "not initialized");
        assertEq(index.totalSupply(), 0, "no shares");
    }

    function testDeployIndexDoesNotRegisterInOfficialIndexManager() public {
        uint256 deployedBefore = indexManager.getDeployedIndexes().length;
        uint256 initializedBefore = indexManager.getInitializedIndexes().length;

        address index = _deployIndexAs(s_attacker, _defaultParams(), SALT);

        assertFalse(indexManager.isIndexAddress(index), "must not be registered");
        assertEq(
            indexManager.getDeployedIndexes().length,
            deployedBefore,
            "deployed list unchanged"
        );
        assertEq(
            indexManager.getInitializedIndexes().length,
            initializedBefore,
            "initialized list unchanged"
        );
        assertTrue(
            Index(index).getIndexManager() != address(indexManager),
            "rogue index is not managed by the official IndexManager"
        );
    }

    function testDeployIndexEmitsNoEvent() public {
        vm.recordLogs();
        _deployIndexAs(s_attacker, _defaultParams(), SALT);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "factory and Index constructor emit no event");
    }

    function testDeployIndexWithDifferentSaltsProducesDifferentAddresses() public {
        IndexDeployParams memory params = _defaultParams();
        address first = _deployIndexAs(s_attacker, params, SALT);
        address second = _deployIndexAs(s_attacker, params, OTHER_SALT);
        assertTrue(first != second);
        assertEq(second, _expectedIndexAddress(params, s_attacker, OTHER_SALT));
    }

    function testDeployIndexDifferentCallersSameParamsAndSaltProduceDifferentAddresses()
        public
    {
        IndexDeployParams memory params = _defaultParams();
        address byAttacker = _deployIndexAs(s_attacker, params, SALT);
        address byOther = _deployIndexAs(s_otherCaller, params, SALT);

        assertTrue(byAttacker != byOther, "caller is part of the initcode");
        assertEq(Index(byAttacker).getIndexManager(), s_attacker);
        assertEq(Index(byOther).getIndexManager(), s_otherCaller);
    }

    function testFrontRunningWithOfficialSaltCannotOccupyOfficialIndexAddress()
        public
    {
        // A new pair the official IndexManager has not deployed yet: WETH / COMP.
        (address asset0, address asset1) = address(mockWeth) < address(mockComp)
            ? (address(mockWeth), address(mockComp))
            : (address(mockComp), address(mockWeth));
        IndexAsset memory indexAsset0 = IndexAsset({asset: asset0, weightPercentage: weight60});
        IndexAsset memory indexAsset1 = IndexAsset({asset: asset1, weightPercentage: weight40});
        bytes32 officialSalt = keccak256(abi.encodePacked(asset0, asset1));

        IndexDeployParams memory params = _defaultParams();
        params.name = string(abi.encodePacked("Index ", _symbolOf(asset0), "/", _symbolOf(asset1)));
        params.symbol = string(abi.encodePacked("IDX", _symbolOf(asset0), _symbolOf(asset1)));
        params.asset0 = indexAsset0;
        params.asset1 = indexAsset1;
        address officialAddress = _expectedIndexAddress(params, address(indexManager), officialSalt);

        // The attacker replays the exact params and salt the IndexManager will use.
        address rogue = _deployIndexAs(s_attacker, params, officialSalt);
        assertTrue(rogue != officialAddress, "rogue index must land elsewhere");

        vm.prank(deployer);
        (address official, , ) = indexManager.createIndex(
            validFeePercentage,
            indexAsset0,
            indexAsset1
        );
        assertEq(official, officialAddress, "official index deployed at its address");
        assertEq(Index(official).getIndexManager(), address(indexManager));
        assertTrue(indexManager.isIndexAddress(official));
        assertFalse(indexManager.isIndexAddress(rogue));
    }

    // =========================================================================
    //  deployIndex — reverts
    // =========================================================================

    function testDeployIndexRevertsOnSameCallerAndSaltTwice() public {
        IndexDeployParams memory params = _defaultParams();
        _deployIndexAs(s_attacker, params, SALT);

        vm.expectRevert(IndexFactory__IndexDeployFailed.selector);
        _deployIndexAs(s_attacker, params, SALT);
    }

    function testDeployIndexRevertsIfIndexConstructorReverts() public {
        // decimals() reverts when the caller has no code, i.e. for the Index under construction.
        IndexDeployParams memory params = _defaultParams();
        params.asset1 = IndexAsset({
            asset: address(new ConstructorDecimalsRevertingTokenMock()),
            weightPercentage: weight40
        });

        vm.expectRevert(IndexFactory__IndexDeployFailed.selector);
        _deployIndexAs(s_attacker, params, SALT);
    }

    // =========================================================================
    //  Index constructor
    // =========================================================================

    function testIndexConstructorRevertsWithZeroIndexManager() public {
        bytes memory initCode = _buildInitCode(_defaultParams(), address(0));
        vm.expectRevert(Index__ZeroAddress.selector);
        s_rawDeployer.deploy(initCode);
    }

    function testIndexConstructorAcceptsNonZeroIndexManager() public {
        bytes memory initCode = _buildInitCode(_defaultParams(), s_attacker);
        address index = s_rawDeployer.deploy(initCode);
        assertEq(Index(index).getIndexManager(), s_attacker);
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _symbolOf(address _token) internal view returns (string memory) {
        return IERC20Metadata(_token).symbol();
    }
}
