--!nonstrict
--[=[
	Utility functions for animations with reactive programming support
	@class AnimationUtils
]=]

local RunService = game:GetService('RunService')
const require = require("../Loader").load()

local Brio = require('Brio')
local EnumUtils = require('EnumUtils')
local Maid = require('Maid')
local RbxAssetUtils = require('RbxAssetUtils')
local Rx = require('Rx')

local AnimationUtils = {}

function AnimationUtils.loadAnimationFromId(
	animatorOrHumanoid: Humanoid | Animator,
	animationId: string
): AnimationTrack
	local animation = Instance.new('Animation')
	animation.AnimationId = animationId
	return (animatorOrHumanoid :: any):LoadAnimation(animation)
end

function AnimationUtils.setWeightTargetIfNotSet(track: AnimationTrack, weight: number, fadeTime: number): ()
	assert(typeof(track) == 'Instance', 'Bad track')
	assert(type(weight) == 'number', 'Bad weight')
	assert(type(fadeTime) == 'number', 'Bad fadeTime')

	if track.WeightTarget ~= weight then
		track:AdjustWeight(weight, fadeTime)
	end
end

function AnimationUtils.getOrCreateAnimator(
	target: Humanoid | AnimationController | Animator | Model | Player,
	warnIfCreatedOnClient: boolean?
): Animator
	assert(typeof(target) == 'Instance', 'Bad target')
	if target:IsA('Animator') then
		return target
	elseif target:IsA('Player') then
		local character = target.Character
		assert(character, 'Player has no character')
		return AnimationUtils.getOrCreateAnimator(character, warnIfCreatedOnClient)
	elseif target:IsA('Model') then
		local descendantAnimator = target:FindFirstChildWhichIsA('Animator', true)
		if descendantAnimator then
			return descendantAnimator
		end

		local controller = target:FindFirstChildOfClass('Humanoid')
			or target:FindFirstChildOfClass('AnimationController')
		if not controller then
			controller = Instance.new('AnimationController')
			controller.Name = 'AnimationController'
			controller.Parent = target
		end
		return AnimationUtils.getOrCreateAnimator(controller, warnIfCreatedOnClient)
	end

	local animator = target:FindFirstChildOfClass('Animator')
	if animator ~= nil then
		return animator
	end

	if RunService:IsClient() and warnIfCreatedOnClient ~= false then
		warn(
			string.format(
				'[HumanoidAnimatorUtils.getOrCreateAnimator] - Creating an animator on %s on the client',
				target:GetFullName()
			)
		)
	end

	local newAnimator = Instance.new('Animator')
	newAnimator.Name = 'Animator'
	newAnimator.Parent = target
	return newAnimator
end

function AnimationUtils.getOrCreateAnimationTrack(
	target: Animator | Player | Model | Humanoid | AnimationController,
	id: string | number,
	priority: Enum.AnimationPriority?
): AnimationTrack?
	assert(typeof(target) == 'Instance', 'Bad target')
	assert(RbxAssetUtils.isConvertableToRbxAsset(id), 'Bad id')
	assert(priority == nil or EnumUtils.isOfType(Enum.AnimationPriority, priority), 'Bad priority')

	local animator = AnimationUtils.getOrCreateAnimator(target :: any)
	if not animator then
		return nil
	end

	assert(typeof(animator) == 'Instance' and animator:IsA('Animator'), 'Bad animator')

	local foundAnimationTrack = AnimationUtils.findAnimationTrackInAnimator(animator, id, priority)
	if foundAnimationTrack then
		return foundAnimationTrack
	end

	local animation = AnimationUtils.getOrCreateAnimationFromIdInAnimator(animator, id, priority)

	local animationTrack
	local ok, err = pcall(function()
		animationTrack = animator:LoadAnimation(animation)
	end)
	if not ok then
		warn(
			string.format(
				'[AnimationUtils] - Failed to load animation with id %q due to %q',
				tostring(id),
				tostring(err)
			)
		)
		return nil
	end

	if priority then
		animationTrack.Priority = priority
	end

	return animationTrack
end

function AnimationUtils.getOrCreateAnimationFromIdInAnimator(
	animator: Animator,
	id: string | number,
	priority: Enum.AnimationPriority?
): Animation
	assert(typeof(animator) == 'Instance' and animator:IsA('Animator'), 'Bad animator')
	assert(RbxAssetUtils.isConvertableToRbxAsset(id), 'Bad id')
	assert(priority == nil or EnumUtils.isOfType(Enum.AnimationPriority, priority), 'Bad priority')

	local animationId = RbxAssetUtils.toRbxAssetId(id)
	for _, animation in animator:GetChildren() do
		if animation:IsA('Animation') then
			if animation.AnimationId == animationId then
				return animation
			end
		end
	end

	local animation = AnimationUtils.createAnimationFromId(id)
	animation.Parent = animator

	return animation
end

function AnimationUtils.stopAnimations(humanoid: Humanoid, fadeTime: number)
	local animator = AnimationUtils.getOrCreateAnimator(humanoid)

	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(fadeTime)
	end
end

function AnimationUtils.stopAnimation(
	target: Animator | Player | Model | Humanoid | AnimationController,
	id: string | number,
	fadeTime: number?
): AnimationTrack?
	assert(typeof(target) == 'Instance', 'Bad target')
	assert(RbxAssetUtils.isConvertableToRbxAsset(id), 'Bad id')
	assert(type(fadeTime) == 'number' or fadeTime == nil, 'Bad fadeTime')

	local animationTrack = AnimationUtils.findAnimationTrack(target, id)

	if animationTrack then
		animationTrack:Stop(fadeTime)
	end

	return animationTrack
end

function AnimationUtils.isPlayingAnimationTrack(humanoid: Humanoid, track: AnimationTrack): boolean
	local animator = AnimationUtils.getOrCreateAnimator(humanoid)

	for _, playingTrack in animator:GetPlayingAnimationTracks() do
		if playingTrack == track then
			return true
		end
	end

	return false
end

function AnimationUtils.isMatchingAnimationTrack(
	animationTrack: AnimationTrack,
	id: string | number,
	priority: Enum.AnimationPriority?
): boolean
	assert(typeof(animationTrack) == 'Instance' and animationTrack:IsA('AnimationTrack'), 'Bad animationTrack')
	assert(RbxAssetUtils.isConvertableToRbxAsset(id), 'Bad id')
	assert(priority == nil or EnumUtils.isOfType(Enum.AnimationPriority, priority), 'Bad priority')

	local animation = animationTrack.Animation
	if not animation then
		return false
	end

	local animationId = RbxAssetUtils.toRbxAssetId(id)
	if animation.AnimationId ~= animationId then
		return false
	end

	if priority and animationTrack.Priority ~= priority then
		return false
	end

	return true
end

function AnimationUtils.findAnimationTrack(
	target: Animator | Player | Model | Humanoid | AnimationController,
	id: string | number,
	priority: Enum.AnimationPriority?
): AnimationTrack?
	assert(typeof(target) == 'Instance', 'Bad target')
	assert(RbxAssetUtils.isConvertableToRbxAsset(id), 'Bad id')
	assert(priority == nil or EnumUtils.isOfType(Enum.AnimationPriority, priority), 'Bad priority')

	local animator = AnimationUtils.getOrCreateAnimator(target)
	if not animator then
		return nil
	end

	return AnimationUtils.findAnimationTrackInAnimator(animator, id, priority)
end

function AnimationUtils.findAnimationTrackInAnimator(
	animator: Animator,
	id: string | number,
	priority: Enum.AnimationPriority?
): AnimationTrack?
	assert(typeof(animator) == 'Instance' and animator:IsA('Animator'), 'Bad animator')
	assert(RbxAssetUtils.isConvertableToRbxAsset(id), 'Bad id')

	local animationId = RbxAssetUtils.toRbxAssetId(id)

	for _, animationTrack in animator:GetPlayingAnimationTracks() do
		if AnimationUtils.isMatchingAnimationTrack(animationTrack, animationId, priority) then
			return animationTrack
		end
	end

	return nil
end

function AnimationUtils.createAnimationFromId(id: string | number): Animation
	assert(RbxAssetUtils.isConvertableToRbxAsset(id), 'Bad id')

	local animationId = RbxAssetUtils.toRbxAssetId(id)
	assert(type(animationId) == 'string', 'Bad id')

	local animation = Instance.new('Animation')
	animation.Name = AnimationUtils.getAnimationName(animationId)
	animation.AnimationId = animationId
	animation.Archivable = false

	return animation
end

function AnimationUtils.getAnimationName(animationId: string): string
	return string.format('Animation_%s', animationId)
end

--[=[
	Observes playing animation tracks on an animator.
	Emits Brios for each playing track - Brio is killed when track stops.

	@param animator Animator -- The animator to observe
	@return Observable<Brio<AnimationTrack>> -- Observable that emits Brios wrapping animation tracks
]=]
function AnimationUtils.observePlayingTracksBrio(animator: Animator)
	return Rx.observable(function(observer)
		local maid = Maid.new()
		local trackBrios = {} :: { [AnimationTrack]: Brio.Brio<AnimationTrack> }

		local function addTrack(track: AnimationTrack)
			if trackBrios[track] then
				return -- Already tracking this
			end

			local brio = Brio.new(track)
			trackBrios[track] = brio
			observer.next(brio)

			-- Kill brio when track stops
			local connection = track.Stopped:Connect(function()
				if trackBrios[track] then
					trackBrios[track]:Kill()
					trackBrios[track] = nil
				end
			end)

			brio:ToMaid():GiveTask(connection)
		end

		local function removeTrack(track: AnimationTrack)
			local brio = trackBrios[track]
			if brio then
				brio:Kill()
				trackBrios[track] = nil
			end
		end

		-- Add existing playing tracks
		for _, track in animator:GetPlayingAnimationTracks() do
			addTrack(track)
		end

		-- Listen for new tracks (we'll poll since there's no direct event)
		local lastTracks = {}
		for _, track in animator:GetPlayingAnimationTracks() do
			lastTracks[track] = true
		end

		maid:GiveTask(RunService.Heartbeat:Connect(function()
			local currentTracks = {}
			for _, track in animator:GetPlayingAnimationTracks() do
				currentTracks[track] = true
				if not lastTracks[track] then
					addTrack(track)
				end
			end

			-- Check for removed tracks
			for track in lastTracks do
				if not currentTracks[track] then
					removeTrack(track)
				end
			end

			lastTracks = currentTracks
		end))

		return function()
			for _, brio in trackBrios do
				brio:Kill()
			end
			maid:DoCleaning()
		end
	end)
end

--[=[
	Observes a specific animation track by ID on an animator.
	Emits a Brio when the track starts playing, kills it when it stops.

	@param animator Animator -- The animator to observe
	@param animationId string | number -- The animation ID to watch for
	@param priority Enum.AnimationPriority? -- Optional priority filter
	@return Observable<Brio<AnimationTrack>> -- Observable that emits a Brio when the animation plays
]=]
function AnimationUtils.observeAnimationTrackBrio(
	animator: Animator,
	animationId: string | number,
	priority: Enum.AnimationPriority?
)
	return AnimationUtils.observePlayingTracksBrio(animator):pipe(Rx.filter(function(brio)
		if brio:IsDead() then
			return false
		end
		local track = brio:GetValue()
		return AnimationUtils.isMatchingAnimationTrack(track, animationId, priority)
	end))
end

--[=[
	Observes animation track properties reactively.

	@param track AnimationTrack -- The track to observe
	@param propertyName string -- The property to observe
	@return Observable<any> -- Observable that emits property values
]=]
function AnimationUtils.observeTrackProperty(track: AnimationTrack, propertyName: string)
	return Rx.fromSignal(function(emit)
		emit((track :: any)[propertyName])
		local connection = track:GetPropertyChangedSignal(propertyName):Connect(function()
			emit((track :: any)[propertyName])
		end)
		return function()
			connection:Disconnect()
		end
	end)
end

--[=[
	Observes when an animation track reaches a specific time position.

	@param track AnimationTrack -- The track to observe
	@param targetTime number -- The time position to watch for
	@return Observable<number> -- Observable that emits when the target time is reached
]=]
function AnimationUtils.observeTrackTimeReached(track: AnimationTrack, targetTime: number)
	return AnimationUtils.observeTrackProperty(track, 'TimePosition')
		:pipe(Rx.filter(function(timePosition)
			return timePosition >= targetTime
		end))
		:pipe(Rx.take(1)) -- Only emit once when reached
end

--[=[
	Observes animation track state changes (playing, stopped, paused).

	@param track AnimationTrack -- The track to observe
	@return Observable<string> -- Observable that emits state strings
]=]
function AnimationUtils.observeTrackState(track: AnimationTrack)
	return Rx.fromSignal(function(emit)
		local function emitState()
			if track.IsPlaying then
				emit('playing')
			else
				emit('stopped')
			end
		end

		emitState() -- Emit initial state

		local playedConnection = track.Played:Connect(function()
			emit('playing')
		end)

		local stoppedConnection = track.Stopped:Connect(function()
			emit('stopped')
		end)

		local pausedConnection = track.Paused:Connect(function()
			emit('paused')
		end)

		return function()
			playedConnection:Disconnect()
			stoppedConnection:Disconnect()
			pausedConnection:Disconnect()
		end
	end)
end

--[=[
	Creates a reactive animation controller that manages track lifecycle.

	@param animator Animator -- The animator to control
	@param animationId string | number -- The animation ID
	@param priority Enum.AnimationPriority? -- Optional priority
	@return table -- Controller with reactive methods
]=]
function AnimationUtils.createReactiveAnimationController(
	animator: Animator,
	animationId: string | number,
	priority: Enum.AnimationPriority?
)
	local controller = {}

	-- Observable for the current track (emits Brio when playing)
	controller.trackBrio = AnimationUtils.observeAnimationTrackBrio(animator, animationId, priority)

	-- Observable for track state
	controller.state = controller.trackBrio:pipe(Rx.switchMap(function(brio)
		if brio:IsDead() then
			return Rx.of('stopped')
		end
		local track = brio:GetValue()
		return AnimationUtils.observeTrackState(track)
	end))

	-- Observable for track time position
	controller.timePosition = controller.trackBrio:pipe(Rx.switchMap(function(brio)
		if brio:IsDead() then
			return Rx.of(0)
		end
		local track = brio:GetValue()
		return AnimationUtils.observeTrackProperty(track, 'TimePosition')
	end))

	-- Observable for track weight
	controller.weight = controller.trackBrio:pipe(Rx.switchMap(function(brio)
		if brio:IsDead() then
			return Rx.of(0)
		end
		local track = brio:GetValue()
		return AnimationUtils.observeTrackProperty(track, 'WeightCurrent')
	end))

	-- Methods
	function controller:play(fadeTime: number?)
		local track = AnimationUtils.getOrCreateAnimationTrack(animator, animationId, priority)
		if track then
			track:Play(fadeTime)
		end
		return self
	end

	function controller:stop(fadeTime: number?)
		local track = AnimationUtils.findAnimationTrackInAnimator(animator, animationId, priority)
		if track then
			track:Stop(fadeTime)
		end
		return self
	end

	function controller:adjustWeight(weight: number, fadeTime: number?)
		local track = AnimationUtils.findAnimationTrackInAnimator(animator, animationId, priority)
		if track then
			track:AdjustWeight(weight, fadeTime or 0)
		end
		return self
	end

	function controller:setSpeed(speed: number)
		local track = AnimationUtils.findAnimationTrackInAnimator(animator, animationId, priority)
		if track then
			track:AdjustSpeed(speed)
		end
		return self
	end

	-- Reactive methods that return observables
	function controller:onTimeReached(targetTime: number)
		return self.trackBrio:pipe(Rx.switchMap(function(brio)
			if brio:IsDead() then
				return Rx.of() -- Empty observable
			end
			local track = brio:GetValue()
			return AnimationUtils.observeTrackTimeReached(track, targetTime)
		end))
	end

	function controller:onStateChange(targetState: string)
		return self.state:pipe(Rx.filter(function(state)
			return state == targetState
		end))
	end

	return controller
end

--[=[
	Creates a reactive animation sequence that plays animations in order.

	@param animator Animator -- The animator to use
	@param sequence {animationId: string | number, duration?: number, fadeTime?: number}[] -- Sequence of animations
	@return Observable<string> -- Observable that emits animation IDs as they play
]=]
function AnimationUtils.createAnimationSequence(animator: Animator, sequence: { any })
	return Rx.observable(function(observer)
		local maid = Maid.new()
		local currentIndex = 1

		local function playNext()
			if currentIndex > #sequence then
				observer.complete()
				return
			end

			local step = sequence[currentIndex]
			local animationId = step.animationId
			local duration = step.duration
			local fadeTime = step.fadeTime

			observer.next(animationId)

			local track = AnimationUtils.getOrCreateAnimationTrack(animator, animationId)
			if not track then
				currentIndex += 1
				playNext()
				return
			end

			track:Play(fadeTime)

			if duration then
				-- Wait for specific duration
				maid:GiveTask(task.delay(duration, function()
					track:Stop(fadeTime)
					currentIndex += 1
					playNext()
				end))
			else
				-- Wait for animation to end
				local connection = track.Stopped:Connect(function()
					currentIndex += 1
					playNext()
				end)
				maid:GiveTask(connection)
			end
		end

		playNext()

		return function()
			maid:DoCleaning()
		end
	end)
end

--[=[
	Observes animation events (markers) in an animation track.

	@param track AnimationTrack -- The track to observe
	@return Observable<{name: string, time: number}> -- Observable that emits animation events
]=]
function AnimationUtils.observeAnimationEvents(track: AnimationTrack)
	return Rx.fromSignal(function(emit)
		local connection = track:GetMarkerReachedSignal():Connect(function(markerName, markerTime)
			emit({
				name = markerName,
				time = markerTime,
			})
		end)

		return function()
			connection:Disconnect()
		end
	end)
end

return AnimationUtils
