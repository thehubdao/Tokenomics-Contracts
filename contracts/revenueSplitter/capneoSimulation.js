class price {
    constructor(initialValue, increaseFactor) {
        this.value = initialValue;
        this.increaseFactor = increaseFactor;
    }
    increase = () => {this.value *= this.increaseFactor}
    decrease = () => {this.value *= 0.99}
}

let totalSaleAmount;
let floorPrice = new price(350, 1.01);
let mintPrice  = new price(400, 1.02);

const buy = () => {
    totalSaleAmount += mintPrice.value;
    floorPrice.increase();
    mintPrice.increase();
}

const nextRound = () => {
    mintPrice.decrease();
    if(mintPrice.value < floorPrice.value) mintPrice.value = floorPrice.value;
}

for(let i = 0; i < 100; i++) {
    let x = Math.random();
    if(x > 0.6) buy();
    else nextRound();
}

for(let i = 0; i < 100; i++) {
    if(mintPrice.value < floorPrice.value * 1.05) {
        let x = Math.random();
        if(x > 0.6) buy();
        else nextRound();
    }
}

console.log({floorPrice, mintPrice})