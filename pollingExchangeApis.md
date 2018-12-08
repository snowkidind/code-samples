# Polling Apis for Exchange Data

When polling cryptocurrency exchanges for latest price information, you have several options towards integrating a trading bot. You can access most exchanges’ REST api, and get relevant last information quite easily, or you can (usually) get a web socket that contains the latest trades in a real time data stream. Further there are some services that poll all the exchanges and give you averaged real time price information or even specific exchange data through their api.

The decision to use any of these methods is all about the application. If you are running an app which makes live trades on a specific exchange you are going to want to get as close to that data as possible, so the websocket or rest api from the exchange in question would most likely be recommended. Else, perhaps you want access to as many exchanges as possible (As is the case with Snowbot) and you want the user to be able to select where he wants his data to come from. 

This leads to a formatting issue when polling from various exchanges because they are all different. Therefore, if you can find a good intermediate api to poll from multiple exchanges you are probably going to be better off if you are not connecting to the respective exchanges to do live trades programmatically.  I found cryptocompare to be free and pretty easy to use…

If you are making orders of any size on non-liquid tokens another consideration to take in mind is the order book. In my experience (with bittrex mostly) order book algorithms can be pretty complex to work with in terms of keeping the book updated with the stream of incoming orders.  You may be able to find some order book examples on Github to integrate liquidity trading into your trading application. If your order book needs are not so real time, for instance detecting buy walls and that sort of thing, you can get a relatively simple version (and a million bugs) up and running pretty easy.

In snowbot’s case graphics are generated from data across many exchanges so the cryptocompare api is a reasonably good fit. (I would eventually have to pay for that service should it scale up)

Additionally, Snowbot has a feature that displays the spread of the order book, which allows its users to determine liquidity of a token at the moment. In this case, it has to be exchange specific, so the application polls some selected exchanges to process that data. Therein, the problem that remains to be solved is a decent way to handle multiple simultaneous api requests in node. 

When Snowbot launches, it polls selected exchanges for the latest available exchange pairs. These calls are part of a longer startup process and multiple subsequent promises are just fine for an application where a user is not waiting on a response.


In Node, your options are Promises, Callback hell, or neither, which is my choice. Promises and callbacks are good for when a process requires synchronous api calls, but in this case, parallel api calls would work just fine, and speed up the process exponentially with some simplistic procedural code:





