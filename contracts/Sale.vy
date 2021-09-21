# @version 0.2.16
"""
@notice Public sale for bootstrapping liquidity
@author avvo.xyz
"""
from vyper.interfaces import ERC20


interface Joe:
    def addLiquidityAVAX(
        token: address,
        amountTokenDesired: uint256,
        amountTokenMin: uint256,
        amountAVAXMin: uint256,
        to: address,
        deadline: uint256,
    ) -> (uint256, uint256, uint256):
        payable


event Purchase:
    buyer: indexed(address)
    amount: uint256


event UpdatePriceMinimum:
    price: uint256[2]
    minimum: uint256


event ChangeBeneficiary:
    beneficiary: indexed(address)


# Liquidity locked for 180 days
LOCK: constant(uint256) = 86400 * 180

# Sale token address
saleToken: public(ERC20)
# Price and price divider
price: public(uint256[2])
# Starts at this timestamp
start: public(uint256)
# Minimum purchase value
minimum: public(uint256)
# Receiver of 25% of this sale
beneficiary: public(address)
# Joe router
joe: public(Joe)
# Total raised
raised: public(uint256)


@external
def __init__(
    _saleToken: address,
    _price: uint256[2],
    _start: uint256,
    _minimum: uint256,
    _uniswap: address,
):
    self.saleToken = ERC20(_saleToken)
    self.price = _price
    self.start = _start
    self.minimum = _minimum
    self.joe = Joe(_uniswap)
    self.beneficiary = msg.sender

    self.saleToken.approve(_uniswap, MAX_UINT256)
    log UpdatePriceMinimum(_price, _minimum)


@external
@payable
def __default__():
    send(self.beneficiary, msg.value)


@internal
def _calculate(amount: uint256) -> uint256:
    return amount * self.price[0] / self.price[1]


@external
@payable
def purchase():
    """
    @notice Purchase tokens
        Adds liquidity to the UNI-V2 pool
        Beneficiary gets 25% of the amount
    """
    assert block.timestamp > self.start, "Sale not started"
    assert msg.value >= self.minimum, "Purchase value below minimum"
    amount: uint256 = self._calculate(msg.value)
    assert self.saleToken.balanceOf(self) >= amount, "Not enough funds for purchase"
    # Transfer purchased tokens to the buyer
    self.saleToken.transfer(msg.sender, amount)
    log Purchase(msg.sender, amount)

    # Beneficiary gets 25% of the sale
    beneficiaryGets: uint256 = msg.value / 4
    send(self.beneficiary, beneficiaryGets)
    # What liquidity gets in ETH (0) and tokens (1)
    liquidityShare: uint256[2] = [
        msg.value - beneficiaryGets,
        self._calculate(msg.value - beneficiaryGets),
    ]
    assert (
        self.saleToken.balanceOf(self) >= liquidityShare[1]
    ), "Insufficient balance for liquidity"
    # Add liquidity to the pool
    self.joe.addLiquidityAVAX(
        self.saleToken.address,
        liquidityShare[1],
        0,
        0,
        self,
        block.timestamp,
        value=liquidityShare[0],
    )

    self.raised += msg.value


@external
def changeBeneficiary(_beneficiary: address):
    """
    @notice Change beneficiary
    @param _beneficiary New beneficiary
    """
    assert msg.sender == self.beneficiary  # dev: not beneficiary
    self.beneficiary = _beneficiary

    log ChangeBeneficiary(_beneficiary)


@external
def unlock(token: address):
    """
    @notice Unlock tokens and transfer to beneficiary when lock is expired
        This allows beneficiary to unlock ANY token and being able to recover it
        including UNI-V2 token and sale token.
    @param token Token to recover
    """
    assert block.timestamp > self.start + LOCK
    ERC20(token).transfer(self.beneficiary, ERC20(token).balanceOf(self))


@external
def changePrice(_price: uint256[2], _minimum: uint256):
    """
    @notice Change sale price
    @param _price New sale price
    @param _minimum New minimum purchase amount
    """
    assert msg.sender == self.beneficiary  # dev: not beneficiary
    self.price = _price
    self.minimum = _minimum
    log UpdatePriceMinimum(_price, _minimum)
