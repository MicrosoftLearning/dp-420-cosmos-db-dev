public record Product(
    string id, 
    string categoryId,
    string categoryName,
    string sku,
    string name,
    string description,
    double price,
    Tag[] tags
);