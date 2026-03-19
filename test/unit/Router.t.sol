import {BaseTest} from "./BaseTest.t.sol";
import {IIndexManager} from "../../src/Interface/IIndexManager.sol";
import {ISwapManager} from "../../src/Interface/ISwapManager.sol";
import {IIndex} from "../../src/Interface/IIndex.sol";
import {IndexAsset, SwapRoute} from "../../src/types.sol";
import {IRouter} from "../../src/Interface/IRouter.sol";
import {Router} from "../../src/Router.sol";
import {HelperConfig, AssetConfig, NetworkConfig} from "../../script/HelperConfig.s.sol";
import {DeployAndInitNewIndex, RunParams} from "../../script/DeployAndInitNewIndex.s.sol";


contract RouterTest is BaseTest {
    //ovverride setuP function per avere diversi index deployati
    
}