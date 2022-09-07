const { expectRevert, time, BN } = require('@openzeppelin/test-helpers');
const { MAX_UINT256 } = require('@openzeppelin/test-helpers/src/constants');
const assert = require('assert');
const vest = artifacts.require('DACVesting');
const ERC20 = artifacts.require('ERC20Mock');

const duration = 10; // in days
const startIn = 1;   // in days


contract('vest', ([alice, owner]) => {
  before(async () => {
    this.MGH = await ERC20.new('MetaGameHub', 'MGH', 2100000, { from: owner });
    this.V = await vest.new();
    this.V.initialize(
      await this.MGH.address,
      owner,
      startIn,
      duration,
      0,
      1,
      2
    );
    await this.MGH.transfer(alice, 1000000, { from: owner });
    await this.MGH.approve(await this.V.address, MAX_UINT256, { from: alice });
    await this.MGH.approve(await this.V.address, MAX_UINT256, { from: owner });
    console.log('current Time: ' + (await time.latest()).toString());
    console.log('START TIME: ' + (await this.V.startTime.call()).toString());
  });

  it('depositAllFor and depositFor work and retrieve gives correct amount back', async () => {
    const start = await this.V.startTime.call();
    await this.V.depositFor(alice, 600000, { from: alice });
    await this.V.depositFor(alice, 100000, { from: owner });
    await this.V.depositFor(owner, 500000, { from: owner });
    assert.equal(await this.MGH.balanceOf(await this.V.address), 1200000);
    assert.equal(await this.V.getTotalDeposit(owner), 500000);
    assert.equal(await this.V.getTotalDeposit(alice), 700000);

    assert.equal(await this.V.getRetrievableAmount(alice), 0);
    assert.equal(await this.V.getRetrievablePercentage(), 0);

    await time.increaseTo(start.add(new BN(10)));
    await this.V.depositAllFor(alice, { from: owner });
    assert.equal(await this.V.getTotalDeposit(alice), 1100000);

    await expectRevert(
      this.V.retrieve({ from: alice }),
      'nothing to retrieve',
    );
    await expectRevert(
      this.V.retrieve({ from: owner }),
      'nothing to retrieve',
    );

    await time.increaseTo(await start.add( new BN(duration * 86400 / 7)));
    await this.V.retrieve({ from: alice });

    await expectRevert(
      this.V.retrieve({ from: alice }),
      "nothing to retrieve",
    );
    assert.equal(await this.V.getRetrievablePercentage(), 2);
    assert.equal((await this.MGH.balanceOf(alice)).toString(), "422440");

    await this.V.depositFor(alice, 100000, { from: owner });
    assert.equal(await this.V.getTotalDeposit(alice), 1200000);

    await this.V.retrieve({ from: alice });
    assert.equal((await this.MGH.balanceOf(alice)).toString(), "424480");
    await expectRevert(
      this.V.retrieve({ from: alice }),
      "nothing to retrieve",
    );
    // INCREASE TIME TO HALF THE DURATION; TEST ADMIN FUNCTION
    time.increaseTo(await start.add( new BN(duration * 86400 / 2)));
    await expectRevert(
      this.V.decreaseVesting(alice, 600000, { from: alice }),
      "Ownable: caller is not the owner",
    );
    await expectRevert(
      this.V.decreaseVesting(alice, 1200001, { from: owner }),
      "revert",
    );
    await expectRevert(
      this.V.decreaseVesting(alice, 1200000, { from: owner }),
      "deposit has to be >= drainedAmount",
    );
    await this.V.decreaseVesting(alice, 600000, { from: owner });

    assert.equal(await this.V.getRetrievableAmount(alice), 125520);

    time.increaseTo(await start.add( new BN(duration * 86400 * 9 / 10)));
    await this.V.retrieve({ from: owner });

    await expectRevert(
      this.V.retrieve({ from: owner }),
      "nothing to retrieve",
    );

    await this.V.retrieve({ from: alice });
    assert.equal((await this.MGH.balanceOf(alice)).toString(), "886000");

    time.increaseTo(await start.add( new BN(duration * 86400)));

    await this.V.retrieve({ from: alice });
    await this.V.retrieve({ from: owner });

    assert.equal((await this.MGH.balanceOf(alice)).toString(), "1000000");
    assert.equal((await this.MGH.balanceOf(await this.V.address)).toString(), "600000");

    await this.V.depositFor(alice, 500000, { from: alice });

    // TEST balanceOf funcitonality for Snapshot
    assert.equal((await this.V.balanceOf(alice)).toString(), "1000000");

    await this.V.retrieve({ from: alice });
    assert.equal((await this.MGH.balanceOf(alice)).toString(), "1000000");

    console.log("HOORAY");
  });
});