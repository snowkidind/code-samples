# Polling Api's for Exchange Data

When polling cryptocurrency exchanges for latest price information, you have several options towards integrating a trading bot. You can access most exchanges’ REST api, and get relevant last information quite easily, or you can (usually) get a web socket that contains the latest trades in a real time data stream. Further there are some services that poll all the exchanges and give you averaged real time price information or even specific exchange data through their api.

The decision to use any of these methods is all about the application. If you are running an app which makes live trades on a specific exchange you are going to want to get as close to that data as possible, so the websocket or rest api from the exchange in question would most likely be recommended. Else, perhaps you want access to as many exchanges as possible (As is the case with Snowbot) and you want the user to be able to select where he wants his data to come from. 

This leads to a formatting issue when polling from various exchanges because they are all different. Therefore, if you can find a good intermediate api to poll from multiple exchanges you are probably going to be better off if you are not connecting to the respective exchanges to do live trades programmatically.  I found cryptocompare to be free and pretty easy to use…

If you are making orders of any size on non-liquid tokens another consideration to take in mind is the order book. In my experience (with bittrex mostly) order book algorithms can be pretty complex to work with in terms of keeping the book updated with the stream of incoming orders.  You may be able to find some order book examples on Github to integrate liquidity trading into your trading application. If your order book needs are not so real time, for instance detecting buy walls and that sort of thing, you can get a relatively simple version (and a million bugs) up and running pretty easy.

In snowbot’s case graphics are generated from data across many exchanges so the cryptocompare api is a reasonably good fit. (I would eventually have to pay for that service should it scale up)

Additionally, however, Snowbot has a feature that displays the spread of the order book, which allows its users to determine liquidity of a token at the moment. In this case, it has to be exchange specific, so the application polls some selected exchanges to process that data. 

In order to achieve that, when Snowbot launches, it polls selected exchanges to make a database of the latest available exchange pairs. These calls are part of a longer startup process and multiple subsequent promises are just fine for an application where a user is not waiting on a response.

```javascript
// Bitfinex, rearrange texts and data handling to meet other exchanges ad nauseum...
const getBitfinexListings = new Promise(
    (resolve, reject) => {
        let url = 'https://api.bitfinex.com/v1/symbols';
        request.get(
            url, (error, response, body) => {
                try {
                    let dataWrapper = JSON.parse(body);
                    let data = dataWrapper;
                    resolve({ exchange: 'bitfinex', data: dataWrapper });
                } catch (error){
                    reject(error);
                }
            });
    }
);

```

superceded by...

```javascript
getBitfinexListings.then(function(val){
  let listing = {exchange: 'bitfinex', data: []};
  for (let i = 0; i < val.data.length; i++){
    listing.data.push({pair: self.toFormat(val.data[i]), remote: val.data[i]});
  }
  listings.push(listing);
  readyStateBfx = true;
})
.catch(
  // Log the rejection reason
  (reason) => {
    // TODO: eventually set a timer and retry
    console.log('rejected: bitfinex ('+reason+') here.');
    readyStateBfx = true;
  });
getHitBtcListings.then(function(val){ // ...etc
```
This gets the exchanges synced up with the program but still there is no way of knowing it's finished. So a recursive timer is integrated to check for completion of the listing pairs operation using simple and crude logic, which will then allow the program to begin serving users:

```javascript
function getPairs(){
    if (readyStateBtx && 
        readyStateBin && 
        readyStateBfx && 
        readyStateHitBtc && 
        readyStateLiq && 
        readyStateCrypt && 
        readyStateKucoin && 
        readyStateIdex){
        
        console.log("Listings ready");
        echoListings();
        
        // start candles application
        candles.startCandles(listings);

    } else {
        oneMTimer = setTimeout(function(){getPairs()}, 1000);
    }
}

```

Therein, the problem that remains to be solved is a decent way to handle multiple simultaneous api requests while maximizing the speed at which these resource calls execute. In Node, your external/filesystem (async or sync) callback options are Promises, Callback hell, or neither, which is my choice. Promises and callbacks are good for when a process requires synchronous api calls, but in this case, parallel api calls would work just fine, and speed up the process exponentially with some simplistic procedural code. First though we must determine which exchanges support the selected token pair:

```javascript

    findMatchingPairs: function(query){
        query = String(query);
        
            // iterate indexes for matching pair
            let index = [];
            for (let i = 0; i < listings.length; i++){
                for (let j = 0; j < listings[i].data.length; j++){
                    if (query === listings[i].data[j].pair){
                        index.push({exchange: listings[i].exchange, data: listings[i].data[j].pair});
                    }
                }
            }
            return index;
        }
    },
```

Now that we have an array of available pairings we can poll the respective exchanges for the appropriate data, again using simple, crude logic, eliminating any use of timers and maximizing response time by using a simple iterator within the original callbacks:

_actual code polls 8 exchanges, most removed for redundancy's sake

```javascript
pollExchangeForPairs: function(availablePairs, callback){

        // here we call the exchanges and return the responses...
        let bittrex = false;
        let binance = false;
        let bitfinex = false;

        let responseData = [];

        let done = 0;

        for (let i = 0; i < availablePairs.length; i++){
            if (availablePairs[i].exchange === "bittrex"){
                bittrex = true;
                done += 1;
            }
            else if (availablePairs[i].exchange === "bitfinex"){
                bitfinex = true;
                done += 1;
            }
            else if (availablePairs[i].exchange === "binance"){
                binance = true;
                done += 1;
            }
        }

        if (bittrex) {
            self.queryBittrex(availablePairs[0].data, function (data) {
                responseData.push(data);
                done -= 1;
                if (done === 0)callback (responseData);
            });
        }
        if (bitfinex){
            self.queryBitfinex(availablePairs[0].data, function(data){
                responseData.push(data);
                done -= 1;
                if (done === 0)callback (responseData);
            });}
        if (binance) {
            self.queryBinance(availablePairs[0].data, function (data) {
                responseData.push(data);
                done -= 1;
                if (done === 0)callback (responseData);
            });
        }
    },
```







