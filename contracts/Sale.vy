# @version 0.2.16
"""
@notice Public sale for bootstrapping liquidity
@author avvo.xyz
"""
from vyper.interfaces import ERC20

interface ARouter:
    def addLiquidityAVAX(
        token: address,
        amountTokenDesired: uint256,
        amountTokenMin: uint256,
        amountAVAXMin: uint256,
        to: address,
        deadline: uint256,
    ) -> (uint256, uint256, uint256):
        payable


interface Oracle:
    def latestAnswer() -> uint256:
        view

    def decimals() -> uint256:
        view


event Purchase:
    buyer: indexed(address)
    amount: uint256


event UpdatePriceMinimum:
    price: uint256
    minimum: uint256


event ChangeBeneficiary:
    beneficiary: indexed(address)


# Liquidity locked for 180 days
LOCK: constant(uint256) = 86400 * 180
# 100 / BENEFICIARY_SHARE is the amount beneficiary gets
BENEFICIARY_SHARE: constant(uint256) = 20
# Total number of exchanges
EXCHANGES: constant(uint256) = 2

# Sale token address
saleToken: public(ERC20)
# Price and price divider
price: public(decimal)
# Starts at this timestamp
start: public(uint256)
# Minimum purchase value
minimum: public(uint256)
# Receiver of 25% of this sale
beneficiary: public(address)
# A router (supposed to work with AVAX DEXes)
exchange: public(address[EXCHANGES])
# ChainLink oracle
oracle: public(Oracle)
# Oracle decimals
oracleDecimals: public(uint256)
# Total raised
raised: public(uint256)


@external
def __init__(
    _saleToken: address,
    _price: decimal,
    _start: uint256,
    _minimum: uint256,
    _exchange: address[EXCHANGES],
    _oracle: address,
):
    self.saleToken = ERC20(_saleToken)
    self.price = _price
    self.start = _start
    self.minimum = _minimum
    self.exchange = _exchange
    self.oracle = Oracle(_oracle)
    self.oracleDecimals = 10 ** self.oracle.decimals()
    self.beneficiary = msg.sender

    for i in range(EXCHANGES):
        self.saleToken.approve(_exchange[i], MAX_UINT256)

    log UpdatePriceMinimum(convert(_price * 100.0, uint256), _minimum)


@external
@payable
def __default__():
    send(self.beneficiary, msg.value)


@view
@internal
def _calculate(amount: uint256, additional: decimal = 0.0) -> uint256:
    amountConverted: decimal = (convert(amount, decimal) / 1e18) * (
        convert(self.oracle.latestAnswer(), decimal)
        / convert(self.oracleDecimals, decimal)
    )
    userGets: decimal = amountConverted / self.price

    if additional > 0.0:
        userGets = userGets * additional

    return convert(userGets * 1e18, uint256)


@view
@external
def calculate(amount: uint256) -> uint256:
    """
    @notice Calculate the amount to get in tokens in exchange for amount
    @param amount Amount of AVAX to deposit
    @return Token amount that will be purchased
    """
    return self._calculate(amount)


@external
def convertedPrice(_decimals: uint256) -> uint256:
    """
    @notice Converts token price to uint256
    @param _decimals Amount indice of power of ten
    @return Converted price multiplied by 10 ** _decimals
    """
    return convert(self.price * convert(10 ** _decimals, decimal), uint256)


@external
@payable
def purchase():
    """
    @notice Purchase tokens
        Adds liquidity to the UNI-V2 pool
        Beneficiary gets specified percentage of the amount
    """
    assert block.timestamp > self.start, "Sale not started"
    assert msg.value > self.minimum, "Purchase value must be above minimum"
    amount: uint256 = self._calculate(msg.value)
    assert self.saleToken.balanceOf(self) >= amount, "Not enough funds for purchase"
    # Transfer purchased tokens to the buyer
    self.saleToken.transfer(msg.sender, amount)
    log Purchase(msg.sender, amount)

    # Sends beneficiary share
    beneficiaryGets: uint256 = msg.value / BENEFICIARY_SHARE
    send(self.beneficiary, beneficiaryGets)

    # What liquidity gets in ETH (0) and tokens (1)
    liquidityShare: uint256[2] = [
        (msg.value - beneficiaryGets) / EXCHANGES,
        (self._calculate(msg.value - beneficiaryGets)) / EXCHANGES,
    ]

    # Add liquidity to the pool
    for i in range(EXCHANGES):
        if self.saleToken.balanceOf(self) >= liquidityShare[1]:
            # Divide the liquidity share between allowed exchanges
            ARouter(self.exchange[i]).addLiquidityAVAX(
                self.saleToken.address,
                liquidityShare[1],
                0,
                0,
                self,
                block.timestamp,
                value=liquidityShare[0],
            )

    # It sends remaining amount of the AVAX to the beneficiary
    # This is not beneficiary share but this is amount left in contract
    # Useful in cases where it is not possible to add liquidity
    send(self.beneficiary, self.balance)

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
        This allows address(0) to unlock ANY token and being able to recover it
        including UNI-V2 token and sale token.
    @param token Token to recover
    """
    assert block.timestamp > self.start + LOCK  # dev: lock not expired
    ERC20(token).transfer(ZERO_ADDRESS, ERC20(token).balanceOf(self))


@external
def changePrice(_price: decimal, _minimum: uint256):
    """
    @notice Change sale price
    @param _price New sale price
    @param _minimum New minimum purchase amount
    """
    assert msg.sender == self.beneficiary  # dev: not beneficiary
    self.price = _price
    self.minimum = _minimum
    log UpdatePriceMinimum(convert(_price * 100.0, uint256), _minimum)
