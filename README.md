# mwtest
Building a MediaWiki bot in Lua

# My environment
- Windows 7 x64
- ZeroBrane + LuaDist
- Lua 5.1.5

As there's no os specific calls or libraries used, I think it could also run well on Linux or Mac. Higher versions of Lua is not tested.

## Steps before running
- Set your clock with an internet server (UTC+8)
- Set up your Lua environment and install the dependencies.
- The DYK update code has to run by an admin account (as T:Dyk is cascade protected)
