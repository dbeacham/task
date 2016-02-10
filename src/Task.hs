{-# LANGUAGE OverloadedStrings #-}

module Task where

import Control.Monad.Free

newtype Action = Action T.Text

newtype TaskId = TaskId Int

data Prioriy
  = Batch
  | Important
  deriving (Show, Read, Eq, Ord, Enum)

data Schedule
  = Once
  -- ^ Run the task once. Don't reschedule after completion.
  | Every Int
  -- ^ Schedule the job to be called every `Int` seconds. A task may only be
  -- rescheduled when a previous invocation has been completed.
  deriving (Show, Read, Eq, Ord, Enum)

newtype TaskDefinition = TaskDefinition
  { action   :: T.Text
  , payload  :: BL.ByteString
  , priority :: Priority
  , schedule :: Schedule
  } deriving (Show, Read, Eq, Ord, Enum)

data CompletionStatus
  = Success [TaskDefinition]
  -- ^ Task successfully completed and requires a new set of tasks to be
  -- scheduled.
  | Error T.Text Bool
  -- ^ Unable to complete task for given reason and whether or not to
  -- retry (reschedule) the task or to pause it.

data TaskException
  = AlreadyCompleted
  | DuplicateOfIncompleteTask TaskId

data CommandF k
  = Create TaskDefinition (Int -> k)
  -- ^ Create a new task
  | Pause TaskId (Bool -> k)
  -- ^ Pause the given task
  | Restart TaskId (Bool -> k)
  -- ^ Restart the associated task
  | Complete TaskId (CompletionStatus -> k)
  -- ^ Complete task with either an error and a time to reschedule or as a
  -- success with a new list of generated tasks to be scheduled.
  | Duplicate TaskId
  -- ^ Duplicate and schedule the given task

data TaskEvent
  = Created TaskId TaskDefinition
  | Paused TaskId
  | Restarted TaskId
  | Completed TaskId CompletionStatus


