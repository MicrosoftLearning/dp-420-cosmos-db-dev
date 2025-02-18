from pydantic import BaseModel

class CompletionRequest(BaseModel):
    message: str
    chat_history: list = []
    max_history: int = 6