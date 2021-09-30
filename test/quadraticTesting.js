const { expectRevert, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256 } = require('@openzeppelin/test-helpers/src/constants');
const assert = require('assert');
const vest = artifacts.require('QuadraticVesting');
const ERC20 = artifacts.require('mockERC20');

const duration = 10; // in days
const startIn = 1;   // in days

contract('vest', ([alice, bob, ben, minter]) => {
  beforeEach(async () => {
    this.MGH = await ERC20.new('MetaGameHub', 'MGH', 1000000, { from: minter });
    this.V = await vest.new(this.MGH.address, duration, startIn);
    await this.MGH.transfer(alice, 800000, { from: minter });
    await this.MGH.transfer(bob, 200000, { from: minter });
    await this.MGH.approve(await this.V.address, MAX_UINT256, { from: bob });
    await this.MGH.approve(await this.V.address, MAX_UINT256, { from: alice });
    console.log('current Time: ' + (await time.latest()).toString());
    console.log('START TIME: ' + (await this.V.startTime.call()).toString());
  });

  describe('deposit', () => {

    it('should be possible to deposit before and after startTime for any account', async () => {
      const start = await this.V.startTime.call();
      await this.V.depositFor(bob, 200000, { from: bob });
      await this.V.depositFor(alice, 600000, { from: alice });
      await this.V.depositFor(ben, 100000, { from: alice });
      assert.equal(await this.MGH.balanceOf(await this.V.address), 900000);
      assert.equal(await this.V.getTotalBalance(ben), 100000);
      assert.equal(await this.V.getTotalBalance(bob), 200000);
      assert.equal(await this.V.getTotalBalance(alice), 600000);
    
      assert.equal(await this.V.getRetrievableAmount(bob), 0);
      time.increaseTo(new BN(start));
      await this.V.depositFor(bob, 100000, { from: alice });
      await expectRevert(
        this.V.retrieve({ from: bob }),
        'nothing to retrieve',
      );
      assert.equal(await this.MGH.balanceOf(this.V.address), 1000000);
    });
  });


  it('deposit for beneficiary and retrieve before start', async () => {
    await this.MGH.approve(await this.V.address, MAX_UINT256, { from: bob });
    //cannot retrieve anything before start of vesting:
    await this.V.depositFor(ben, 200000, { from: bob });
    assert.equal(await this.MGH.balanceOf(await this.V.address), 200000);
    assert.equal(await this.V.getRetrievableAmount(bob), 0);
    assert.equal(await this.V.getRetrievableAmount(ben), 0);
    await expectRevert(
      this.V.retrieve({ from: bob }),
      'nothing to retrieve',
    );
    await expectRevert(
       this.V.retrieve({ from: ben }),
       'nothing to retrieve',
    );
    assert.equal(await this.MGH.balanceOf(this.V.address), 200000);
    assert.equal(await this.V.getTotalBalance(ben), 200000);
    assert.equal(await this.V.getTotalBalance(bob), 0);
    assert.equal(await this.V.getRetrievablePercentage(), 0);
  });

  it('deposit for self and benificiary before and after start and withdraw at 1/7 and 1/2 and 1 and 2 of the duration', async () => {
    const start = await this.V.startTime.call();
    await this.MGH.approve(await this.V.address, MAX_UINT256, { from: alice });
    await this.MGH.approve(await this.V.address, MAX_UINT256, { from: bob });
    await this.V.depositFor(alice, 700000, { from: alice });
    await this.V.depositFor(bob, 100000, { from: bob });
    await this.V.depositFor(ben, 100000, { from: bob });
    assert.equal(await this.MGH.balanceOf(await this.V.address), 900000);
    await time.increaseTo(await start.add( new BN(duration * 86400 / 7)));
    let currently = (await time.latest()).toString();
    console.log("85: " + currently);

    await this.V.retrieve({ from: ben });
    assert.equal((await this.V.getRetrievablePercentage()).toString(), '2');
    assert.equal((await this.MGH.balanceOf(ben)).toString(), '2040');
    await time.increaseTo(await start.add( new BN(duration * 86400 / 2)));
    assert.equal((await this.V.getRetrievablePercentage()).toString(), '25');
    await this.V.retrieve( { from: ben });
    assert.equal((await this.MGH.balanceOf(ben)).toString(), '25000');
    await time.increaseTo(await start.add( new BN (duration * 86400)));
    await this.V.retrieve( { from: ben });
    await this.V.retrieve( { from: alice });
    assert.equal((await this.MGH.balanceOf(ben)).toString(), '100000');
    assert.equal((await this.MGH.balanceOf(alice)).toString(), '800000');
    await time.increaseTo(await start.add( new BN( 2 * duration * 86400)));
    await this.V.retrieve({ from: bob });
    await expectRevert(
      this.V.retrieve({ from: ben }),
      'nothing to retrieve',
    );
    await expectRevert(
      this.V.retrieve({ from: alice }),
      'nothing to retrieve',
    );
    assert.equal((await this.MGH.balanceOf(this.V.address)).toString(), '0');
    assert.equal((await this.MGH.balanceOf(bob)).toString(), '100000');
  });
});