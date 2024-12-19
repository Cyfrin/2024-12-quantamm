//SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./UpliftOnlyExample.sol";

/** 
 * @notice This contract is a simple ERC721 contract for LP NFTs. It overrides update which means
 * that the deposits can be transferred feely between users.
 * this does require the router to change the vault balances and deposit records as well
 */

/// @title LPNFT contract for QuantAMM LP NFTs 
/// @notice implements ERC721 for LP NFTs 
contract LPNFT is ERC721 {

    uint256 numMinted;

    /// @notice the address of the QuantAMM router this token is for
    UpliftOnlyExample public router;

    /// @notice Modifier for only allowing the router to call certain functions
    modifier onlyUpliftOnlyRouter() {
        require(msg.sender == address(router), "ROUTERONLY"); 
        _;
    }


    constructor(
        string memory _name,
        string memory _symbol,
        address _router
    ) ERC721(_name, _symbol) {
        router = UpliftOnlyExample(payable(_router));
    }

    /// @param _to the address to mint the NFT to
    function mint(address _to) public onlyUpliftOnlyRouter returns (uint256 tokenId) {
        tokenId = ++numMinted; // We start minting at 1
        _mint(_to, tokenId);
    }

    /// @param _tokenId the id of the NFT to burn
    function burn(uint256 _tokenId) public onlyUpliftOnlyRouter {
        _burn(_tokenId);
    }

    /// @inheritdoc ERC721
    function _update(address to, uint256 tokenId, address auth) internal override returns (address previousOwner) {
        previousOwner  = super._update(to, tokenId, auth);
        //_update is called during mint, burn and transfer. This functionality is only for transfer
        if (to != address(0) && previousOwner != address(0)) {
            //if transfering the record in the vault needs to be changed to reflect the change in ownership
            router.afterUpdate(previousOwner, to, tokenId);
        }
    }
}
