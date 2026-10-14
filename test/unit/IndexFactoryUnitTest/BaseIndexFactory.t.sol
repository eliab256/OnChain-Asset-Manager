// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../Base.t.sol";
import {Index} from "../../../src/Index.sol";
import {IndexAsset, IndexDeployParams} from "../../../src/types.sol";
import {SplitCodeHarness} from "../../mocks/SplitCodeHarness.sol";
import {RawCreateDeployerMock} from "../../mocks/RawCreateDeployerMock.sol";

/**
 * @dev Shared setup for the IndexFactory unit tests. Reuses the full periphery from BaseTest
 *      (IndexManager, Router, PriceFeedManager, SwapManager, mocks) and the IndexFactory deployed
 *      by DeployPeriphery. Contains no test functions.
 */
abstract contract BaseIndexFactoryTest is BaseTest {
    // =========================================================================
    //  Helpers / actors
    // =========================================================================

    SplitCodeHarness internal s_splitCodeHarness;
    RawCreateDeployerMock internal s_rawDeployer;

    /// Arbitrary caller with no role anywhere: the factory is permissionless.
    address internal s_attacker = makeAddr("attacker");
    /// Second arbitrary caller, used to prove the IndexManager (msg.sender) is part of the initcode.
    address internal s_otherCaller = makeAddr("otherCaller");

    // =========================================================================
    //  Constants
    // =========================================================================

    bytes32 internal constant SALT = keccak256("IndexFactoryTest.salt");
    bytes32 internal constant OTHER_SALT = keccak256("IndexFactoryTest.otherSalt");
    string internal constant TEST_INDEX_NAME = "Rogue Index";
    string internal constant TEST_INDEX_SYMBOL = "RIDX";

    // =========================================================================
    //  Values derived from the contracts (assigned in setUp)
    // =========================================================================

    /// Index creation code compiled in this test build (no constructor args).
    bytes internal s_indexCreationCode;
    /// Size of the first half stored by the factory (floor(n/2)) and of the second one.
    uint256 internal s_sizeA;
    uint256 internal s_sizeB;
    /// EIP-170 limit used by SplitCode and the STOP-byte offset of each data contract.
    uint256 internal s_maxCodeSize;
    uint256 internal s_dataOffset;
    /// Largest data accepted by SplitCode.write (runtime == MAX_CODE_SIZE) and the first rejected size.
    uint256 internal s_maxValidDataSize;
    uint256 internal s_invalidDataSize;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public virtual override {
        super.setUp();

        s_splitCodeHarness = new SplitCodeHarness();
        s_rawDeployer = new RawCreateDeployerMock();

        s_indexCreationCode = type(Index).creationCode;
        s_sizeA = s_indexCreationCode.length / 2;
        s_sizeB = s_indexCreationCode.length - s_sizeA;

        s_maxCodeSize = s_splitCodeHarness.exposed_maxCodeSize();
        s_dataOffset = s_splitCodeHarness.exposed_dataOffset();
        s_maxValidDataSize = s_maxCodeSize - s_dataOffset;
        s_invalidDataSize = s_maxValidDataSize + 1;

        vm.label(address(indexFactory), "IndexFactory");
        vm.label(s_attacker, "Attacker");
        vm.label(s_otherCaller, "OtherCaller");
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Valid Index params wired to the official periphery (WETH 60% / LINK 40%, 1% fee).
    function _defaultParams() internal view returns (IndexDeployParams memory) {
        return
            IndexDeployParams({
                name: TEST_INDEX_NAME,
                symbol: TEST_INDEX_SYMBOL,
                router: address(router),
                usdc: address(mockUsdc),
                priceFeedManager: address(priceFeedManager),
                swapManager: address(swapManager),
                universalRouter: address(mockUniRouter),
                asset0: IndexAsset({
                    asset: address(mockWeth),
                    weightPercentage: weight60
                }),
                asset1: IndexAsset({
                    asset: address(mockLink),
                    weightPercentage: weight40
                }),
                feePercentage: validFeePercentage
            });
    }

    /// @dev Expected Index initcode: creation code || abi.encode(constructor args) in the Index order.
    function _buildInitCode(
        IndexDeployParams memory _params,
        address _indexManager
    ) internal view returns (bytes memory) {
        return
            abi.encodePacked(
                s_indexCreationCode,
                _encodeConstructorArgs(_params, _indexManager)
            );
    }

    function _encodeConstructorArgs(
        IndexDeployParams memory _params,
        address _indexManager
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _params.name,
                _params.symbol,
                _indexManager,
                _params.router,
                _params.usdc,
                _params.priceFeedManager,
                _params.swapManager,
                _params.universalRouter,
                _params.asset0,
                _params.asset1,
                _params.feePercentage
            );
    }

    /// @dev CREATE2 address the factory must produce for `_caller` (the IndexManager baked in the initcode).
    function _expectedIndexAddress(
        IndexDeployParams memory _params,
        address _caller,
        bytes32 _salt
    ) internal view returns (address) {
        return
            vm.computeCreate2Address(
                _salt,
                keccak256(_buildInitCode(_params, _caller)),
                address(indexFactory)
            );
    }

    function _deployIndexAs(
        address _caller,
        IndexDeployParams memory _params,
        bytes32 _salt
    ) internal returns (address index) {
        vm.prank(_caller);
        index = indexFactory.deployIndex(_params, _salt);
    }

    /// @dev Returns `_length` bytes of `_data` starting at `_start`.
    function _slice(
        bytes memory _data,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory slice) {
        slice = new bytes(_length);
        for (uint256 i = 0; i < _length; i++) {
            slice[i] = _data[_start + i];
        }
    }

    /// @dev Bytes filled with a non-zero pattern, used as fake creation code / data.
    function _patternBytes(uint256 _length) internal pure returns (bytes memory data) {
        data = new bytes(_length);
        for (uint256 i = 0; i < _length; i++) {
            data[i] = bytes1(uint8(i % 251) + 1);
        }
    }
}
