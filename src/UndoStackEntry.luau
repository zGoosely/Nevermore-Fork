--!strict

const Implementation = require(script.Parent._Index["quenty/undostack@0.0.1"]["UndoStackEntry"])

export type ExecuteUndo = Implementation.ExecuteUndo
export type ExecuteRedo = Implementation.ExecuteRedo
export type UndoStackEntry = Implementation.UndoStackEntry

return Implementation
