"""All ORM models. Importing this package registers every table on Base.metadata."""

from .agent import ActionProposal, AgentConversation, AgentJob, AgentMemory, AgentMessage, LlmCall
from .identity import DeviceToken, EmailToken, Invite, RefreshToken, User, UserPreferences
from .journal import JournalEntry, MoodEntry
from .learning import LearningPath, LearningTopic, Project, Skill, StudySession
from .productivity import Goal, GoalMilestone, Habit, HabitLog, Reminder, ScheduleBlock, Task
from .progression import Achievement, UserAchievement, XpLedger
from .system import (
    ActivityEvent,
    AuditLog,
    ClientReport,
    DailySummary,
    IdempotencyKey,
    NotificationLog,
    WeeklySummary,
)

__all__ = [
    "Achievement",
    "ActionProposal",
    "ActivityEvent",
    "AgentConversation",
    "AgentJob",
    "AgentMemory",
    "AgentMessage",
    "AuditLog",
    "ClientReport",
    "DailySummary",
    "DeviceToken",
    "EmailToken",
    "Goal",
    "GoalMilestone",
    "Habit",
    "HabitLog",
    "IdempotencyKey",
    "Invite",
    "JournalEntry",
    "LearningPath",
    "LearningTopic",
    "LlmCall",
    "MoodEntry",
    "NotificationLog",
    "Project",
    "RefreshToken",
    "Reminder",
    "ScheduleBlock",
    "Skill",
    "StudySession",
    "Task",
    "User",
    "UserAchievement",
    "UserPreferences",
    "WeeklySummary",
    "XpLedger",
]

# Entities that sync offline and are exported with the account (ARCHITECTURE §15).
SYNC_ENTITIES = {
    "tasks": Task,
    "goals": Goal,
    "goal_milestones": GoalMilestone,
    "habits": Habit,
    "habit_logs": HabitLog,
    "reminders": Reminder,
    "schedule_blocks": ScheduleBlock,
    "mood_entries": MoodEntry,
    "journal_entries": JournalEntry,
    "learning_paths": LearningPath,
    "skills": Skill,
    "learning_topics": LearningTopic,
    "study_sessions": StudySession,
    "projects": Project,
}
