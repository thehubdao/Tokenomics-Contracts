pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract mockERC20 is ERC20 {

    uint8 immutable _decimals;
    function mint(uint256 amount) public {
        _mint(msg.sender, amount * 10**18);
    }

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _mint(msg.sender, 10 ** (decimals_ + 6));
        _decimals = decimals_;
    }

    function decimals() public view override returns(uint8) {
        return _decimals;
    }
}