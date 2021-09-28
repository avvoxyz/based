# @version 0.2.16
"""
@notice
    Rebasing token that allows external contract to update the delta (rebase multiplier)
@author avvo.xyz
"""
from vyper.interfaces import ERC20

implements: ERC20


event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    amount: uint256


event Approval:
    sender: indexed(address)
    receiver: indexed(address)
    amount: uint256


event UpdateDelta:
    delta: uint256


event UpdateAdmin:
    admin: indexed(address)


event UpdateOracle:
    oracle: indexed(address)


name: public(String[32])
symbol: public(String[16])
decimals: public(uint256)
supply: uint256

balances: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

delta: public(decimal)
admin: public(address)
oracle: public(address)


@external
def __init__(
    _name: String[32], _symbol: String[16], _decimals: uint256, _supply: uint256
):
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals
    self.supply = _supply * 10 ** _decimals
    self.balances[msg.sender] = self.supply
    self.admin = msg.sender
    self.oracle = msg.sender
    self.delta = 1.0


@internal
@view
def _based(amount: decimal, rebase: bool) -> uint256:
    if rebase:
        return convert(amount * self.delta, uint256)
    else:
        return convert(amount / self.delta, uint256)


@external
def transfer(receiver: address, amount: uint256) -> bool:
    """
    @notice Transfer tokens to receiver
    @param receiver Receiver of tokens
    @param amount Amount to transfer (will be divided by delta)
    @return True
    """
    converted: uint256 = self._based(convert(amount, decimal), False)
    self.balances[msg.sender] -= converted
    self.balances[receiver] += converted
    log Transfer(msg.sender, receiver, amount)
    return True


@external
def transferFrom(sender: address, receiver: address, amount: uint256) -> bool:
    """
    @notice Transfer tokens from sender to receiver
    @param sender Actual owner of tokens
    @param receiver Receiver of tokens
    @param amount Amount to transfer (will be divided by delta)
    @return True
    """
    converted: uint256 = self._based(convert(amount, decimal), False)
    self.allowance[sender][msg.sender] -= converted
    self.balances[sender] -= converted
    self.balances[receiver] += converted
    log Transfer(sender, receiver, amount)
    return True


@external
def approve(receiver: address, amount: uint256) -> bool:
    """
    @notice Give allowance to receiver
    @param receiver Allowance receiver
    @param amount Amount to allow spending
    @return True
    """
    self.allowance[msg.sender][receiver] = amount
    log Approval(msg.sender, receiver, amount)
    return True


@external
@view
def balanceOf(owner: address) -> uint256:
    """
    @notice Get balance of owner
    @param owner Owner of tokens
    @return Balance multiplied by delta
    """
    return self._based(convert(self.balances[owner], decimal), True)


@external
@view
def totalSupply() -> uint256:
    """
    @notice Get total supply
    @return Total supply multiplied by delta
    """
    return self._based(convert(self.supply, decimal), True)


@external
def changeDelta(_delta: decimal):
    """
    @notice Change delta therefore supply and user balances
    @param _delta New delta
    @dev Only oracle can change delta
    """
    assert msg.sender == self.oracle
    self.delta = _delta
    log UpdateDelta(convert(_delta * 100.0, uint256))


@view
@external
def deltaConverted(_decimals: uint256) -> uint256:
    """
    @notice Convert delta to unsigned integer
    @param _decimals Power of 10 to multiply with
    @return Delta multiplied by decimals and converted to uint256
    """
    return convert(self.delta * convert(10 ** _decimals, decimal), uint256)


@external
def changeAdmin(_admin: address):
    """
    @notice Change admin
    @param _admin New admin
    @dev Only admin can change admin
    """
    assert msg.sender == self.admin
    self.admin = _admin
    log UpdateAdmin(_admin)


@external
def changeOracle(_oracle: address):
    """
    @notice Change oracle
    @param _oracle New oracle
    @dev Only admin can change oracle
    """
    assert msg.sender == self.admin
    self.oracle = _oracle
    log UpdateOracle(_oracle)
