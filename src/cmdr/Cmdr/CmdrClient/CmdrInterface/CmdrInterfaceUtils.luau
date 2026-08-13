--!strict
--[=[
	Builds Cmdr completion text and inline ghost-text markup.

	@util CmdrInterfaceUtils
]=]

type AutocompleteItem = { string }

const CmdrInterfaceUtils = {}

const function escapeRichText(text: string): string
	return string.gsub(text, "[&<>'\"]", {
		["&"] = "&amp;",
		["<"] = "&lt;",
		[">"] = "&gt;",
		["'"] = "&apos;",
		["\""] = "&quot;",
	})
end

--[=[
	Builds the text accepted when the selected completion is applied.

	@within CmdrInterfaceUtils
	@param item AutocompleteItem
	@param command any?
	@param lastArgument any?
	@param argumentCount number?
	@param isPartial boolean?
	@return string
]=]
function CmdrInterfaceUtils.getCompletionText(
	item: AutocompleteItem,
	command: any?,
	lastArgument: any?,
	argumentCount: number?,
	isPartial: boolean?
): string
	const replacement: string = item[2]

	if not command then
		return replacement .. " "
	end

	local text = command.Alias
	const shouldInsertSpace = argumentCount ~= #command.ArgumentDefinitions and isPartial == false

	for _, argument in command.Arguments do
		const segments = table.clone(argument.RawSegments)
		if argument == lastArgument then
			segments[#segments] = replacement
		end

		local argumentText = argument.Prefix .. table.concat(segments, ",")
		if string.find(argumentText, " ", 1, true) or argumentText == "" then
			argumentText = string.format("%q", argumentText)
		end

		text = string.format("%s %s", text, argumentText)
		if argument == lastArgument then
			break
		end
	end

	return text .. (shouldInsertSpace and " " or "")
end

--[=[
	Builds a display-only completion that remains aligned with the current text,
	even when accepting the candidate must introduce quotes.

	@within CmdrInterfaceUtils
	@param typedText string
	@param item AutocompleteItem
	@param acceptedText string
	@return string
]=]
function CmdrInterfaceUtils.getGhostCompletionText(
	typedText: string,
	item: AutocompleteItem,
	acceptedText: string
): string
	if string.lower(string.sub(acceptedText, 1, #typedText)) == string.lower(typedText) then
		return acceptedText
	end

	const typedSegment = item[1]
	const replacement = item[2]
	if type(typedSegment) ~= "string" or type(replacement) ~= "string" then
		return typedText
	end
	if #typedSegment > #typedText then
		return typedText
	end
	const typedTail = if typedSegment == "" then "" else string.sub(typedText, -#typedSegment)
	if string.lower(typedTail) ~= string.lower(typedSegment) then
		return typedText
	end
	if string.lower(string.sub(replacement, 1, #typedSegment)) ~= string.lower(typedSegment) then
		return typedText
	end

	const suffix = string.sub(replacement, #typedSegment + 1)
	const trailingSpace = if string.sub(acceptedText, -1) == " " then " " else ""
	return typedText .. suffix .. trailingSpace
end

--[=[
	Returns rich text that hides the typed prefix and shows only the completion
	suffix in translucent gray.

	@within CmdrInterfaceUtils
	@param typedText string
	@param completionText string
	@return string
]=]
function CmdrInterfaceUtils.getGhostRichText(typedText: string, completionText: string): string
	if #completionText <= #typedText then
		return ""
	end
	if string.lower(string.sub(completionText, 1, #typedText)) ~= string.lower(typedText) then
		return ""
	end

	const prefix = escapeRichText(string.sub(completionText, 1, #typedText))
	const suffix = escapeRichText(string.sub(completionText, #typedText + 1))
	return `<font transparency="1">{prefix}</font><font color="#A0A0A0" transparency="0.2">{suffix}</font>`
end

return CmdrInterfaceUtils
