from pydantic import BaseModel

class Product(BaseModel):
    id: str
    category_id: str
    category_name: str
    sku: str
    name: str
    description: str
    price: float
    discount: float = 0.0
    sale_price: float = None
    embedding: list = []
