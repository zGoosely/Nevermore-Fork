--!strict

const require = require("../../Loader").load()

local Observable = require('Observable')

export type ClockFunction = () -> number

export type BaseClock = {
	GetTime: (self: BaseClock) -> number,
	GetPing: (self: BaseClock) -> number,
	IsSynced: (self: BaseClock) -> boolean,
	ObservePing: (self: BaseClock) -> Observable.Observable<number>,
	GetClockFunction: (self: BaseClock) -> ClockFunction,
}

return {}
