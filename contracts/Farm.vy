# @version 0.2.16
"""
@notice Yield farming contract with referral program
    Referral program sends 0.1% of the claimed reward to the referred by
    Referred by needs to hold specific amount of minimumHodl to be eligible

    There is emergency withdraw function for emergency cases, this ignores
    pending rewards and immediately withdraws the whole token balance of user
@author avvo.xyz
"""
from vyper.interfaces import ERC20


event Deposit:
    owner: indexed(address)
    pair: indexed(address)
    amount: uint256


event Claim:
    owner: indexed(address)
    pair: indexed(address)
    amount: uint256


event ReferralClaim:
    receiver: indexed(address)
    amount: uint256


event Withdraw:
    owner: indexed(address)
    pair: indexed(address)
    amount: uint256


event EmergencyWithdraw:
    owner: indexed(address)
    pair: indexed(address)
    amount: uint256


event UpdateFarm:
    pair: indexed(address)
    rate: uint256


struct Deposits:
    amount: uint256
    entrance: uint256
    referredBy: address


struct ReferralProgram:
    enabled: bool
    minimumHodl: uint256


admin: public(address)
reward: public(ERC20)

rates: public(HashMap[address, uint256])
total: public(HashMap[address, uint256])

deposits: public(HashMap[address, HashMap[address, Deposits]])
referralProgram: public(ReferralProgram)


@external
def __init__(_reward: address):
    self.reward = ERC20(_reward)
    self.admin = msg.sender


@view
@internal
def _pending(user: address, pair: address) -> uint256:
    deposit: Deposits = self.deposits[user][pair]
    if (deposit.amount == 0) or (deposit.entrance == 0):
        return 0

    return min(
        (
            (self.rates[pair] / ((ERC20(pair).balanceOf(self) / deposit.amount)))
            * (block.timestamp - deposit.entrance)
        ),
        self.reward.balanceOf(self),
    )


@internal
def _claim(user: address, pair: address) -> bool:
    pending: uint256 = self._pending(user, pair)
    if pending == 0:
        return False

    self.reward.transfer(user, pending)

    # Referral program
    referredBy: address = self.deposits[user][pair].referredBy
    if (referredBy != ZERO_ADDRESS) and self.referralProgram.enabled:
        referralReward: uint256 = min(pending / 1000, self.reward.balanceOf(self))
        # Check if there are any rewards and if any, check if referred by is eligible
        # to receive rewards
        if (referralReward > 0) and (
            self.reward.balanceOf(referredBy) >= self.referralProgram.minimumHodl
        ):
            self.reward.transfer(referredBy, referralReward)
            log ReferralClaim(referredBy, referralReward)

    self.deposits[user][pair].entrance = block.timestamp
    log Claim(user, pair, pending)
    return True


@view
@external
def pending(user: address, pair: address) -> uint256:
    return self._pending(user, pair)


@external
@nonreentrant("lock")
def deposit(pair: address, amount: uint256, referral: address = ZERO_ADDRESS):
    """
    @notice Deposit assets
    @param pair Pair to deposit
    @param amount Amount to deposit
    @param referral Address to reward 0.1% of claims
    @dev Reward for pair must be higher than 0
    """
    assert self.rates[pair] > 0, "Pair not available for farming"
    updated: bool = self._claim(msg.sender, pair)

    ERC20(pair).transferFrom(msg.sender, self, amount)
    self.deposits[msg.sender][pair].amount += amount

    if not updated and (amount > 0):
        self.deposits[msg.sender][pair].entrance = block.timestamp

    if (self.deposits[msg.sender][pair].referredBy == ZERO_ADDRESS) and (
        referral != ZERO_ADDRESS
    ):
        # User does not have any referral set before, adding referral
        self.deposits[msg.sender][pair].referredBy = referral

    log Deposit(msg.sender, pair, amount)


@external
@nonreentrant("lock")
def claim(pair: address):
    """
    @notice Claim pending rewards
    @param pair Pair with pending rewards
    @dev Reverts if rewards cannot be claimed
    """
    assert self._claim(msg.sender, pair)


@external
@nonreentrant("lock")
def withdraw(pair: address, amount: uint256):
    """
    @notice Withdraw assets
    @param pair Pair to withdraw
    @param amount Amount to withdraw
    """
    self._claim(msg.sender, pair)
    self.deposits[msg.sender][pair].amount -= amount
    ERC20(pair).transfer(msg.sender, amount)

    if self.deposits[msg.sender][pair].amount == 0:
        self.deposits[msg.sender][pair].entrance = 0

    log Withdraw(msg.sender, pair, amount)


@external
@nonreentrant("lock")
def emergencyWithdraw(pair: address):
    """
    @notice Withdraw without claiming rewards
    @param pair Pair to withdraw
    """
    deposit: uint256 = self.deposits[msg.sender][pair].amount
    self.deposits[msg.sender][pair].amount = 0
    self.deposits[msg.sender][pair].entrance = 0

    ERC20(pair).transfer(msg.sender, deposit)
    log EmergencyWithdraw(msg.sender, pair, deposit)


@external
def updateFarm(pair: address, rate: uint256):
    """
    @notice Update rewards for pair
    @param pair Pair to update reward rate
    @param rate New reward rate
    @dev Only admin can change reward rate
    """
    assert msg.sender == self.admin  # dev: not admin
    assert pair != self.reward.address  # dev: cannot accept reward token
    self.rates[pair] = rate
    log UpdateFarm(pair, rate)


@external
def updateReferral(enabled: bool, minimumHodl: uint256):
    """
    @notice Update referral program status
    @param enabled Whether it is enabled or not
    @dev Only admin can change referral program status
    """
    assert msg.sender == self.admin  # dev: not admin
    self.referralProgram = ReferralProgram({enabled: enabled, minimumHodl: minimumHodl})
