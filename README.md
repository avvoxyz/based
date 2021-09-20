# avvo smart contracts

Smart contracts under this repository are written from scratch and therefore probably risky to use.

All of the smart contracts (rebasing token, strategy alpha, farm and sale) is available under [contracts/](contracts/) directory.

### Simply Reproducible

You may easily compile Vyper smart contracts with following snippet:
```
vyper RebasingToken.vy
```
and this will output the smart contract bytecode which you can later compare with the deployed bytecode.