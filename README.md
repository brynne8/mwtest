# mwtest
Building a MediaWiki bot in Lua

# My environment
- Windows 7 x64
- ZeroBrane + LuaDist
- Lua 5.1.5

As there's no os specific calls or libraries used, I think it could also run well on Linux or Mac. Higher versions of Lua is not tested.

## dykupdate
- Set your clock with an internet server (UTC+8)
- Set up your Lua environment and install the dependencies.
- The DYK update code has to run by an admin account (as T:Dyk is cascade protected)

## linky
This is a Lua version of linky for QQ using [CoolQ Socket API](https://github.com/mrhso/cqsocketapi). CoolQ and your client communicates using UDP sockets. Timerwheel is used for sending ClientHello every 5 minutes. Lua-iconv is used for encoding and decoding between GB18030 and UTF-8.