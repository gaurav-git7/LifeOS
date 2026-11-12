import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    display_name: str
    timezone: str
    role: str
    level: int
    total_xp: int
    email_verified_at: datetime | None
    created_at: datetime


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=200)
    display_name: str = Field(min_length=1, max_length=80)
    timezone: str = "UTC"
    invite_code: str | None = None
    device_label: str | None = Field(default=None, max_length=80)


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(max_length=200)
    device_label: str | None = Field(default=None, max_length=80)


class RefreshIn(BaseModel):
    refresh_token: str


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserRead


class TokenIn(BaseModel):
    token: str


class EmailIn(BaseModel):
    email: EmailStr


class ResetIn(BaseModel):
    token: str
    new_password: str = Field(max_length=200)


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str = Field(max_length=200)


class Message(BaseModel):
    message: str
