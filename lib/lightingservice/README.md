# PostProcessingStackService

`PostProcessingStackService` owns shared, named post-processing effects on the
client. Each effect exposes property stacks backed by `StateStack`, so temporary
overrides restore the previous value when their cleanup function is called.

```luau
const PostProcessingStackService = require("PostProcessingStackService")

const postProcessing = serviceBag:GetService(PostProcessingStackService)
const blur = postProcessing:GetOrCreateEffect("MenuBlur", "BlurEffect")

local removeBlur = blur:PushProperty("Size", 24)
removeBlur()
```

For more control, retrieve a property stack directly:

```luau
const sizeStack = blur:GetPropertyStack("Size")
local removeFirst = sizeStack:PushState(12)
local removeSecond = sizeStack:PushState(24)

removeSecond() -- Restores 12.
removeFirst() -- Restores the original BlurEffect.Size.
```
