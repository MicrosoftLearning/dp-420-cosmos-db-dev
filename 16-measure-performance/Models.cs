using System.Collections.Generic;

public class CustomerV2
{
    public string id { get; set; }
    public string title { get; set; }
    public string firstName { get; set; }
    public string lastName { get; set; }
    public string emailAddress { get; set; }
    public string phoneNumber { get; set; }
    public string creationDate { get; set; }
    public List<CustomerAddress> addresses { get; set; }
    public Password password { get; set; }
}

public class CustomerAddress
{
    public string addressLine1 { get; set; }
    public string addressLine2 { get; set; }
    public string city { get; set; }
    public string state { get; set; }
    public string country { get; set; }
    public string zipCode { get; set; }
    public Location location { get; set; }
}

public class Location
{
    public string type { get; set; }
    public List<float> coordinates { get; set; }
}

public class Password
{
    public string hash { get; set; }
    public string salt { get; set; }
}

public class ProductCategory
{
    public string id { get; set; }
    public string name { get; set; }
    public string type { get; set; }
}

public class Product
{
    public string id { get; set; }
    public string categoryId { get; set; }
    public string categoryName { get; set; }
    public string sku { get; set; }
    public string name { get; set; }
    public string description { get; set; }
    public double price { get; set; }
    public List<Tag> tags { get; set; }
}

public class Tag
{
    public string id { get; set; }
    public string name { get; set; }
}

public class SalesOrder
{
    public string id { get; set; }
    public string type { get; set; }
    public string customerId { get; set; }
    public string orderDate { get; set; }
    public string shipDate { get; set; }
    public List<SalesOrderDetails> details { get; set; }
}

public class SalesOrderDetails
{
    public string sku { get; set; }
    public string name { get; set; }
    public double price { get; set; }
    public int quantity { get; set; }
}

public class CustomerV4
{
    public string id { get; set; }
    public string type { get; set; }
    public string customerId { get; set; }
    public string title { get; set; }
    public string firstName { get; set; }
    public string lastName { get; set; }
    public string emailAddress { get; set; }
    public string phoneNumber { get; set; }
    public string creationDate { get; set; }
    public List<CustomerAddress> addresses { get; set; }
    public Password password { get; set; }
    public int salesOrderCount { get; set; }
}

public class CategorySales
{
    public string id { get; set; }
    public string categoryId { get; set; }
    public string categoryName { get; set; }
    public int totalSales { get; set; }
}


public class GitFileInfo
{
    public string name;
    public string type;
    public long size;
    public string download_url;
}