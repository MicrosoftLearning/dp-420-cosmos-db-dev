---
title: '07.3 - Build a copilot with Python and Azure Cosmos DB for NoSQL'
lab:
    title: '07.3 - Build a copilot with Python and Azure Cosmos DB for NoSQL'
    module: 'Build copilots with Python and Azure Cosmos DB for NoSQL'
layout: default
nav_order: 12
parent: 'Python SDK labs'
---

# Build a copilot with Python and Azure Cosmos DB for NoSQL

By utilizing Python's versatile programming capabilities and Azure Cosmos DB's scalable NoSQL database and vector search capabilities, you can create powerful and efficient AI copilots, streamlining complex workflows.

In this lab, you will build a copilot using Python and Azure Cosmos DB for NoSQL, creating a backend API that will provide endpoints necessary for interacting with Azure services (Azure OpenAI and Azure Cosmos DB) and a frontend UI to facilitate user interaction with the copilot. The copilot will serve as an assistant for helping Cosmic Works users manage and find bicycle-related products. Specifically, the copilot will enable users to apply and remove discounts from categories of products, look up product categories to help inform users of what product types are available, and use vector search to perform similarity searches for products.

![A high-level copilot architecture diagram, showing a UI developed in Python using Streamlit, a backend API written in Python, and interactions with Azure Cosmos DB and Azure OpenAI.](media/07-copilot-high-level-architecture-diagram.png)

Separating app functionality into a dedicated UI and backend API when creating a copilot in Python offers several benefits. Firstly, it enhances modularity and maintainability, allowing you to update the UI or backend independently without disrupting the other. Streamlit provides an intuitive and interactive interface that simplifies user interactions, while FastAPI ensures high-performance, asynchronous request handling and data processing. This separation also promotes scalability, as different components can be deployed across multiple servers, optimizing resource usage. Additionally, it enables better security practices, as the backend API can handle sensitive data and authentication separately, reducing the risk of exposing vulnerabilities in the UI layer. This approach leads to a more robust, efficient, and user-friendly application.

> &#128721; The previous exercises in this module are prerequisites for this lab. If you still need to complete any of those exercises, please finish them before continuing, as they provide the necessary infrastructure and starter code for this lab.

## Construct a backend API

The backend API for the copilot enriches its abilities to handle intricate data, provide real-time insights, and connect seamlessly with diverse services, making interactions more dynamic and informative. To build the API for your copilot, you will use the FastAPI Python library. FastAPI is a modern, high-performance web framework designed to enable you to build APIs with Python based on standard Python type hints. By decoupling the copilot from the backend using this approach, you ensure greater flexibility, maintainability, and scalability, allowing the copilot to evolve independently from backend changes.

> &#128721; The backend API builds upon the code you added to the `main.py` file in the `python/07-build-copilot/api/app` folder in the previous exercise. If you have not yet finished the previous exercise, please complete it before continuing.

1. Using Visual Studio Code, open the folder into which you cloned the lab code repository for **Build copilots with Azure Cosmos DB** learning module.

1. In the **Explorer** pane within Visual Studio Code, browse to the **python/07-build-copilot/api/app** folder and open the `main.py` file found within it.

1. Add the following lines of code below the existing `import` statements at the top of the `main.py` file to bring in the libraries that will be used to perform asychronous actions using FastAPI:

   ```python
   from contextlib import asynccontextmanager
   from fastapi import FastAPI
   import json
   ```

1. To enable the `/chat` endpoint you will create to receive data in the request body, you will pass content in via a `CompletionRequest` object defined in the projects *models* module. Update the `from models import Product` import statement at the top of the file to include the `CompletionRequest` class from the `models` module. The import statement should now look like this:

   ```python
   from models import Product, CompletionRequest
   ```

1. You will need the deployment name of the chat completion model you created in your Azure OpenAI Service. Create a variable at the bottom of the Azure OpenAI configuration variable block to provide this:

   ```python
   COMPLETION_DEPLOYMENT_NAME = 'gpt-4o'
   ```

    If your completion deployment name differs, update the value assigned to the variable accordingly.

1. The Azure Cosmos DB and Identity SDKs provide async methods for working with those services. Each of these classes will used in multiple functions in your API, so you will create global instances of each, allowing the same client to be shared across methods. Insert the following global variable declarations below the Cosmos DB configuration variables block:

   ```python
   # Create a global async Cosmos DB client
   cosmos_client = None
   # Create a global async Microsoft Entra ID RBAC credential
   credential = None
   ```

1. Delete the following lines of code from the file, as the functionality provided will be moved into the `lifespan` function you will define in the next step:

   ```python
   # Enable Microsoft Entra ID RBAC authentication
   credential = DefaultAzureCredential()
   ```

1. To create singleton instances of the `CosmosClient` and `DefaultAzureCredentail` classes, you will take advantage of the `lifespan` object in FastAPI: This method manages those classes through the lifecycle of the API app. Insert the following code to define the `lifespan`:

   ```python
   @asynccontextmanager
   async def lifespan(app: FastAPI):
       global cosmos_client
       global credential
       # Create an async Microsoft Entra ID RBAC credential
       credential = DefaultAzureCredential()
       # Create an async Cosmos DB client using Microsoft Entra ID RBAC authentication
       cosmos_client = CosmosClient(url=AZURE_COSMOSDB_ENDPOINT, credential=credential)
       yield
       await cosmos_client.close()
       await credential.close()
   ```

   In FastAPI, lifespan events are special operations that run at the beginning and end of the application's life cycle. These operations execute before the app starts handling requests and after it stops, making them ideal for initializing and cleaning up resources that are used across the entire application and shared between requests. This approach ensures that necessary setup is completed before any requests are processed and that resources are properly managed when shutting down.

1. Create an instance of the FastAPI class using the following code. This should be inserted below the `lifespan` function:

   ```python
   app = FastAPI(lifespan=lifespan)
   ```

   By calling `FastAPI()`, you are initializing a new instance of the FastAPI application. This instance, referred to as `app`, will serve as the main entry point for your web application. Passing in the `lifespan` attaches the lifespan event handler to your app.

1. Next, stub out the endpoints for your API. The `api_status` method is attached to the root URL of your API and acts as a status message to show that the API is up and running correctly. You will build out the `/chat` endpoint later in this exercise. Insert the following code below the code for creating the Cosmos DB client, database and container:

   ```python
   @app.get("/")
   async def api_status():
       """Display a status message for the API"""
       return {"status": "ready"}
    
   @app.post('/chat')
   async def generate_chat_completion(request: CompletionRequest):
       """Generate a chat completion using the Azure OpenAI API."""
       raise NotImplementedError("The chat endpoint is not implemented yet.")
   ```

1. Overwrite the main guard block at the bottom of the file to start the `uvicorn` ASGI (Asynchronous Server Gateway Interface) web server when the file is run from the command line:

   ```python
   if __name__ == "__main__":
       import uvicorn
       uvicorn.run(app, host="0.0.0.0", port=8000)
   ```

1. Save the `main.py` file. It should now look like the following, including the `generate_embeddings` and `upsert_product` methods you added in the pervious exercise:

   ```python
   from openai import AsyncAzureOpenAI
   from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider
   from azure.cosmos.aio import CosmosClient
   from models import Product, CompletionRequest
   from contextlib import asynccontextmanager
   from fastapi import FastAPI
   import json
    
   # Azure OpenAI configuration
   AZURE_OPENAI_ENDPOINT = "<AZURE_OPENAI_ENDPOINT>"
   AZURE_OPENAI_API_VERSION = "2024-10-21"
   EMBEDDING_DEPLOYMENT_NAME = "text-embedding-3-small"
   COMPLETION_DEPLOYMENT_NAME = 'gpt-4o'
    
   # Azure Cosmos DB configuration
   AZURE_COSMOSDB_ENDPOINT = "<AZURE_COSMOSDB_ENDPOINT>"
   DATABASE_NAME = "CosmicWorks"
   CONTAINER_NAME = "Products"
    
   # Create a global async Cosmos DB client
   cosmos_client = None
   # Create a global async Microsoft Entra ID RBAC credential
   credential = None
   
   @asynccontextmanager
   async def lifespan(app: FastAPI):
       global cosmos_client
       global credential
       # Create an async Microsoft Entra ID RBAC credential
       credential = DefaultAzureCredential()
       # Create an async Cosmos DB client using Microsoft Entra ID RBAC authentication
       cosmos_client = CosmosClient(url=AZURE_COSMOSDB_ENDPOINT, credential=credential)
       yield
       await cosmos_client.close()
       await credential.close()
    
   app = FastAPI(lifespan=lifespan)
    
   @app.get("/")
   async def api_status():
       return {"status": "ready"}
    
   @app.post('/chat')
   async def generate_chat_completion(request: CompletionRequest):
       """ Generate a chat completion using the Azure OpenAI API."""
       raise NotImplementedError("The chat endpoint is not implemented yet.")
    
   async def generate_embeddings(text: str):
       # Create Azure OpenAI client
       async with AsyncAzureOpenAI(
           api_version = AZURE_OPENAI_API_VERSION,
           azure_endpoint = AZURE_OPENAI_ENDPOINT,
           azure_ad_token_provider = get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")
       ) as client:
           response = await client.embeddings.create(
               input = text,
               model = EMBEDDING_DEPLOYMENT_NAME
           )
           return response.data[0].embedding
    
   async def upsert_product(product: Product):
       """Upserts the provided product to the Cosmos DB container."""
       # Create an async Cosmos DB client
       async with CosmosClient(url=AZURE_COSMOSDB_ENDPOINT, credential=credential) as client:
           # Load the CosmicWorks database
           database = client.get_database_client(DATABASE_NAME)
           # Retrieve the product container
           container = database.get_container_client(CONTAINER_NAME)
           # Upsert the product
           await container.upsert_item(product)
    
   if __name__ == "__main__":
       import uvicorn
       uvicorn.run(app, host="0.0.0.0", port=8000)
   ```

1. To quickly test your API, open a new integrated terminal window in Visual Studio Code.

1. Ensure you are logged into Azure using the `az login` command. Running the following at the terminal prompt:

   ```bash
   az login
   ```

1. Complete the login process in your browser.

1. Change directories to `python/07-build-copilot` at the terminal prompt.

1. Ensure the integrated terminal window runs within your Python virtual environment by activating it using a command from the table below and selecting the appropriate command for your OS and shell.

    | Platform | Shell | Command to activate virtual environment |
    | -------- | ----- | --------------------------------------- |
    | POSIX | bash/zsh | `source .venv/bin/activate` |
    | | fish | `source .venv/bin/activate.fish` |
    | | csh/tcsh | `source .venv/bin/activate.csh` |
    | | pwsh | `.venv/bin/Activate.ps1` |
    | Windows | cmd.exe | `.venv\Scripts\activate.bat` |
    | | PowerShell | `.venv\Scripts\Activate.ps1` |

1. At the terminal prompt, change directories to `api/app`, then execute the following command to run the FastAPI web app:

   ```bash
   uvicorn main:app
   ```

1. If one does not open automatically, launch a new web browser window or tab and go to <http://127.0.0.1:8000>.

    A message of `{"status":"ready"}` in the browser window indicates your API is running.

1. Navigate to the Swagger UI for the API by appending `/docs` to the end of the URL: <http://127.0.0.1:8000/docs>.

    > &#128221; The Swagger UI is an interactive, web-based interface for exploring and testing API endpoints generated from OpenAPI specifications. It allows developers and users to visualize, interact with, and debug real-time API calls, enhancing usability and documentation.

1. Return to Visual Studio Code and stop the API app by pressing **CTRL+C** in the associated integrated terminal window.

## Incorporate product data from Azure Cosmos DB

By leveraging data from Azure Cosmos DB, the copilot can streamline complex workflows and assist users in efficiently completing tasks. The copilot can update records and retrieve lookup values in real time, ensuring accurate and timely information. This capability enables the copilot to provide advanced interactions, enhancing users' ability to quickly and precisely navigate and complete tasks.

Functions will allow the product management copilot to apply discounts to products within a category. These functions will be the mechanism through which the copilot retrieves and interacts with Cosmic Works product data from Azure Cosmos DB.

1. The copilot will use an async function named `apply_discount` to add and remove discounts and sale prices on products within a specified category. Insert the following function code below the `upsert_product` function near the bottom of the `main.py` file:

   ```python
   async def apply_discount(discount: float, product_category: str) -> str:
       """Apply a discount to products in the specified category."""
       # Load the CosmicWorks database
       database = cosmos_client.get_database_client(DATABASE_NAME)
       # Retrieve the product container
       container = database.get_container_client(CONTAINER_NAME)
    
       query_results = container.query_items(
           query = """
           SELECT * FROM Products p WHERE CONTAINS(LOWER(p.category_name), LOWER(@product_category))
           """,
           parameters = [
               {"name": "@product_category", "value": product_category}
           ]
       )
    
       # Apply the discount to the products
       async for item in query_results:
           item['discount'] = discount
           item['sale_price'] = item['price'] * (1 - discount) if discount > 0 else item['price']
           await container.upsert_item(item)
    
       return f"A {discount}% discount was successfully applied to {product_category}." if discount > 0 else f"Discounts on {product_category} removed successfully."
   ```

    This function performs a lookup in Azure Cosmos DB to pull all products within a category and apply the requested discount to those products. It also calculates the item's sale price using the specified discount and inserts that into the database.

2. Next, you will add a second function named `get_category_names`, which the copilot will call to assist it in knowing what product categories are available when applying or removing discounts from products. Add the below method below the `apply_discount` function in the file:

   ```python
   async def get_category_names() -> list:
       """Retrieve the names of all product categories."""
       # Load the CosmicWorks database
       database = cosmos_client.get_database_client(DATABASE_NAME)
       # Retrieve the product container
       container = database.get_container_client(CONTAINER_NAME)
       # Get distinct product categories
       query_results = container.query_items(
           query = "SELECT DISTINCT VALUE p.category_name FROM Products p"
       )
       categories = []
       async for category in query_results:
           categories.append(category)
       return list(categories)
   ```

    The `get_category_names` function queries the `Products` container to retrieve a list of distinct category names from the database.

3. Save the `main.py` file.

## Implement the chat endpoint

The `/chat` endpoint on the backend API serves as the interface through which the frontend UI interacts with Azure OpenAI models and internal Cosmic Works product data. This endpoint acts as the communication bridge, allowing UI input to be sent to the Azure OpenAI service, which then processes these inputs using sophisticated language models. The results are then returned to the front end, enabling real-time, intelligent conversations. By leveraging this setup, developers can ensure a seamless and responsive user experience while the backend handles the complex task of processing natural language and generating appropriate responses. This approach also supports scalability and maintainability by decoupling the front end from the underlying AI infrastructure.

1. Locate the `/chat` endpoint stub you added previously in the `main.py` file.

   ```python
   @app.post('/chat')
   async def generate_chat_completion(request: CompletionRequest):
       """Generate a chat completion using the Azure OpenAI API."""
       raise NotImplementedError("The chat endpoint is not implemented yet.")
   ```

    The function accepts a `CompletionRequest` as a parameter. Utilizing a class for the input parameter allows multiple properties to be passed into the API endpoint in the request body. The `CompletionRequest` class is defined within the *models* module and includes user message, chat history, and max history properties. The chat history allows the copilot to reference previous aspects of the conversation with the user, so it maintains knowledge of the context of the entire discussion. The `max_history` property allows you to define the number of history messages should be passed into the context of the LLM. This enables you to control token usages for your prompt and avoid TPM limits on requests.

2. To start, delete the `raise NotImplementedError("The chat endpoint is not implemented yet.")` line from the function as you are beginning the process of implementing the endpoint.

3. The first thing you will do within the chat endpoint method is provide a system prompt. This prompt defines the copilots "persona," dictacting how the copilot should interact with users, respond to questions, and leverage available functions to perform actions.

   ```python
   # Define the system prompt that contains the assistant's persona.
   system_prompt = """
   You are an intelligent copilot for Cosmic Works designed to help users manage and find bicycle-related products.
   You are helpful, friendly, and knowledgeable, but can only answer questions about Cosmic Works products.
   If asked to apply a discount:
       - Apply the specified discount to all products in the specified category. If the user did not provide you with a discount percentage and a product category, prompt them for the details you need to apply a discount.
       - Discount amounts should be specified as a decimal value (e.g., 0.1 for 10% off).
   If asked to remove discounts from a category:
       - Remove any discounts applied to products in the specified category by setting the discount value to 0.
   """
   ```

4. Next, create an array of messages to send to the LLM, adding the system prompt, any messages in the chat history, and the incoming user message. This code should go directly below the system prompt declaration in the function:

   ```python
   # Provide the copilot with a persona using the system prompt.
   messages = [{"role": "system", "content": system_prompt }]
    
   # Add the chat history to the messages list
   for message in request.chat_history[-request.max_history:]:
       messages.append(message)
    
   # Add the current user message to the messages list
   messages.append({"role": "user", "content": request.message})
   ```

    The `messages` property encapsulates the ongoing conversation's history. It includes the entire sequence of user inputs and the AI's responses, which helps the model maintain context. By referencing this history, the AI can generate coherent and contextually relevant replies, ensuring that interactions remain fluid and dynamic. This property is crucial for enabling the AI to understand the flow and nuances of the conversation as it progresses.

5. To allow the copilot to use the functions you defined above for interacting with data from Azure Cosmos DB, you must define a collection of "tools." The LLM will call these tools as part of its execution. Azure OpenAI uses function definitions to enable structured interactions between the AI and various tools or APIs. When a function is defined, it describes the operations it can perform, the necessary parameters, and any required inputs. To create an array of `tools`, provide the following code containing function definitions for the `apply_discount` and `get_category_names` methods you previously defined:

   ```python
   # Define function calling tools
   tools = [
       {
           "type": "function",
           "function": {
               "name": "apply_discount",
               "description": "Apply a discount to products in the specified category",
               "parameters": {
                   "type": "object",
                   "properties": {
                       "discount": {"type": "number", "description": "The percent discount to apply."},
                       "product_category": {"type": "string", "description": "The category of products to which the discount should be applied."}
                   },
                   "required": ["discount", "product_category"]
               }
           }
       },
       {
           "type": "function",
           "function": {
               "name": "get_category_names",
               "description": "Retrieves the names of all product categories"
           }
       }
   ]
   ```

    By using function definitions, Azure OpenAI ensures that interactions between the AI and external systems are well-organized, secure, and efficient. This structured approach allows the AI to perform complex tasks seamlessly and reliably, enhancing its overall capabilities and user experience.

6. Create an async Azure OpenAI client for making requests to your chat completion model:

   ```python
   # Create Azure OpenAI client
   aoai_client = AsyncAzureOpenAI(
       api_version = AZURE_OPENAI_API_VERSION,
       azure_endpoint = AZURE_OPENAI_ENDPOINT,
       azure_ad_token_provider = get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")
   )
   ```

7. The chat endpoint will make two calls to Azure OpenAI to leverage function calling. The first provides the Azure OpenAI client access to the tools:

   ```python
   # First API call, providing the model to the defined functions
   response = await aoai_client.chat.completions.create(
       model = COMPLETION_DEPLOYMENT_NAME,
       messages = messages,
       tools = tools,
       tool_choice = "auto"
   )
    
   # Process the model's response and add it to the conversation history
   response_message = response.choices[0].message
   messages.append(response_message)
   ```

8. The response from this first call contains information from the LLM about what tools or functions it has determined are necessary to respond to the request. You must include code to process the function call outputs, inserting them into the conversation history so the LLM can use them to formulate a response over the data contained within those outputs:

   ```python
   # Handle function call outputs
   if response_message.tool_calls:
       for call in response_message.tool_calls:
           if call.function.name == "apply_discount":
               func_response = await apply_discount(**json.loads(call.function.arguments))
               messages.append(
                   {
                       "role": "tool",
                       "tool_call_id": call.id,
                       "name": call.function.name,
                       "content": func_response
                   }
               )
           elif call.function.name == "get_category_names":
               func_response = await get_category_names()
               messages.append(
                   {
                       "role": "tool",
                       "tool_call_id": call.id,
                       "name": call.function.name,
                       "content": json.dumps(func_response)
                   }
               )
   else:
       print("No function calls were made by the model.")
   ```

    Function calling in Azure OpenAI allows the seamless integration of external APIs or tools directly into your model's output. When the model detects a relevant request, it constructs a JSON object with the necessary parameters, which you then execute. The result is returned to the model, enabling it to deliver a comprehensive final response enriched with external data.

9. To complete the request with the enriched data from Azure Cosmos DB, you need to send a second request to Azure OpenAI to generate a completion:

   ```python
   # Second API call, asking the model to generate a response
   final_response = await aoai_client.chat.completions.create(
       model = COMPLETION_DEPLOYMENT_NAME,
       messages = messages
   )
   ```

10. Finally, return the completion response to the UI:

   ```python
   return final_response.choices[0].message.content
   ```

11. Save the `main.py` file. The `/chat` endpoint's `generate_chat_completion` method should look like this:

   ```python
   @app.post('/chat')
   async def generate_chat_completion(request: CompletionRequest):
       """Generate a chat completion using the Azure OpenAI API."""
       # Define the system prompt that contains the assistant's persona.
       system_prompt = """
       You are an intelligent copilot for Cosmic Works designed to help users manage and find bicycle-related products.
       You are helpful, friendly, and knowledgeable, but can only answer questions about Cosmic Works products.
       If asked to apply a discount:
           - Apply the specified discount to all products in the specified category. If the user did not provide you with a discount percentage and a product category, prompt them for the details you need to apply a discount.
           - Discount amounts should be specified as a decimal value (e.g., 0.1 for 10% off).
       If asked to remove discounts from a category:
           - Remove any discounts applied to products in the specified category by setting the discount value to 0.
       """
       # Provide the copilot with a persona using the system prompt.
       messages = [{ "role": "system", "content": system_prompt }]
    
       # Add the chat history to the messages list
       for message in request.chat_history[-request.max_history:]:
           messages.append(message)
    
       # Add the current user message to the messages list
       messages.append({"role": "user", "content": request.message})
    
       # Define function calling tools
       tools = [
           {
               "type": "function",
               "function": {
                   "name": "apply_discount",
                   "description": "Apply a discount to products in the specified category",
                   "parameters": {
                       "type": "object",
                       "properties": {
                           "discount": {"type": "number", "description": "The percent discount to apply."},
                           "product_category": {"type": "string", "description": "The category of products to which the discount should be applied."}
                       },
                       "required": ["discount", "product_category"]
                   }
               }
           },
           {
               "type": "function",
               "function": {
                   "name": "get_category_names",
                   "description": "Retrieves the names of all product categories"
               }
           }
       ]
       # Create Azure OpenAI client
       aoai_client = AsyncAzureOpenAI(
           api_version = AZURE_OPENAI_API_VERSION,
           azure_endpoint = AZURE_OPENAI_ENDPOINT,
           azure_ad_token_provider = get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")
       )
    
       # First API call, providing the model to the defined functions
       response = await aoai_client.chat.completions.create(
           model = COMPLETION_DEPLOYMENT_NAME,
           messages = messages,
           tools = tools,
           tool_choice = "auto"
       )
    
       # Process the model's response
       response_message = response.choices[0].message
       messages.append(response_message)
    
       # Handle function call outputs
       if response_message.tool_calls:
           for call in response_message.tool_calls:
               if call.function.name == "apply_discount":
                   func_response = await apply_discount(**json.loads(call.function.arguments))
                   messages.append(
                       {
                           "role": "tool",
                           "tool_call_id": call.id,
                           "name": call.function.name,
                           "content": func_response
                       }
                   )
               elif call.function.name == "get_category_names":
                   func_response = await get_category_names()
                   messages.append(
                       {
                           "role": "tool",
                           "tool_call_id": call.id,
                           "name": call.function.name,
                           "content": json.dumps(func_response)
                       }
                   )
       else:
           print("No function calls were made by the model.")
    
       # Second API call, asking the model to generate a response
       final_response = await aoai_client.chat.completions.create(
           model = COMPLETION_DEPLOYMENT_NAME,
           messages = messages
       )
    
       return final_response.choices[0].message.content
   ```

## Build a simple chat UI

The Streamlit UI provides a interface for users to interact with your copilot.

1. The UI will be defined using the `index.py` file located in the `python/07-build-copilot/ui` folder.

2. Open the `index.py` file and add the following import statements to the top of the file to get started:

   ```python
   import streamlit as st
   import requests
   ```

3. Configure the Streamlit page defined within the `index.py` file by adding the following line below the `import` statements:

   ```python
   st.set_page_config(page_title="Cosmic Works Copilot", layout="wide")
   ```

4. The UI will interact with the backend API by using the `requests` library to make calls to the `/chat` endpoint you defined on the API. You can encapsulate the API call in a method that expects the current user message and a list of messages from the chat history.

   ```python
   async def send_message_to_copilot(message: str, chat_history: list = []) -> str:
       """Send a message to the Copilot chat endpoint."""
       try:
           api_endpoint = "http://localhost:8000"
           request = {"message": message, "chat_history": chat_history}
           response = requests.post(f"{api_endpoint}/chat", json=request, timeout=60)
           return response.json()
       except Exception as e:
           st.error(f"An error occurred: {e}")
           return""
   ```

5. Define the `main` function, which is the entry point for calls into the application.

   ```python
   async def main():
       """Main function for the Cosmic Works Product Management Copilot UI."""
    
       st.write(
           """
           # Cosmic Works Product Management Copilot
        
           Welcome to Cosmic Works Product Management Copilot, a tool for managing and finding bicycle-related products in the Cosmic Works system.
        
           **Ask the copilot to apply or remove a discount on a category of products or to find products.**
           """
       )
    
       # Add a messages collection to the session state to maintain the chat history.
       if "messages" not in st.session_state:
           st.session_state.messages = []
    
       # Display message from the history on app rerun.
       for message in st.session_state.messages:
           with st.chat_message(message["role"]):
               st.markdown(message["content"])
    
       # React to user input
       if prompt := st.chat_input("What can I help you with today?"):
           with st. spinner("Awaiting the copilot's response to your message..."):
               # Display user message in chat message container
               with st.chat_message("user"):
                   st.markdown(prompt)
                
               # Send the user message to the copilot API
               response = await send_message_to_copilot(prompt, st.session_state.messages)
    
               # Display assistant response in chat message container
               with st.chat_message("assistant"):
                   st.markdown(response)
                
               # Add the current user message and assistant response messages to the chat history
               st.session_state.messages.append({"role": "user", "content": prompt})
               st.session_state.messages.append({"role": "assistant", "content": response})
   ```

6. Finally, add a **main guard** block at the end of the file:

   ```python
   if __name__ == "__main__":
       import asyncio
       asyncio.run(main())
   ```

7. Save the `index.py` file.

## Test the copilot via the UI

1. Return to the integrated terminal window you opened in Visual Studio Code for the API project and enter the following to start the API app:

   ```bash
   uvicorn main:app
   ```

2. Open a new integrated terminal window, change directories to `python/07-build-copilot` to activate your Python environment, then change directories to the `ui` folder and run the following to start your UI app:

   ```bash
   python -m streamlit run index.py
   ```

3. If the UI does not open automatically in a browser window, launch a new browser tab or window and navigate to <http://localhost:8501> to open the UI.

4. At the chat prompt of the UI, enter "Apply discount" and send the message.

    Because you needed to provide the copilot with more details to act, the response should be a request for more information, such as providing the discount percentage you'd like to apply and the category of products to which the discount should be applied.

5. To understand what categories are available, ask the copilot to provide you with a list of product categories.

    The copilot will make a function call using the `get_category_names` function and enrich the conversation messages with those categories so it can respond accordingly.

6. You can also ask for a more specific set of categories, such as, "Provide me with a list of clothing-related categories."

7. Next, ask the copilot to apply a 15% discount to all clothing products.

8. You can verify the pricing discount was applied by opening your Azure Cosmos DB account in the Azure portal, selecting the **Data Explorer**, and running a query against the `Products` container to view all products in the "clothing" category, such as:

   ```sql
   SELECT c.category_name, c.name, c.description, c.price, c.discount, c.sale_price FROM c
   WHERE CONTAINS(LOWER(c.category_name), "clothing")
   ```

    Observe that each item in the query results has a `discount` value of `0.15`, and the `sale_price` should be 15% less than the original `price`.

9. Return to Visual Studio Code and stop the API app by pressing **CTRL+C** in the terminal window running that app. You can leave the UI running.

## Integrate vector search

So far, you have given the copilot the ability to perform actions to apply discounts to products, but it still has no knowledge of the products stored within the database. In this task, you will add vector search capabilities that will allow you to ask for products with certain qualities and find similar products within the database.

1. Return to the `main.py` file in the `api/app` folder and provide a method for performing vector searches against the `Products` container in your Azure Cosmos DB account. You can insert this method below the existing functions near the bottom of the file.

   ```python
   async def vector_search(query_embedding: list, num_results: int = 3, similarity_score: float = 0.25):
       """Search for similar product vectors in Azure Cosmos DB"""
       # Load the CosmicWorks database
       database = cosmos_client.get_database_client(DATABASE_NAME)
       # Retrieve the product container
       container = database.get_container_client(CONTAINER_NAME)
    
       query_results = container.query_items(
           query = """
           SELECT TOP @num_results p.name, p.description, p.sku, p.price, p.discount, p.sale_price, VectorDistance(p.embedding, @query_embedding) AS similarity_score
           FROM Products p
           WHERE VectorDistance(p.embedding, @query_embedding) > @similarity_score
           ORDER BY VectorDistance(p.embedding, @query_embedding)
           """,
           parameters = [
               {"name": "@query_embedding", "value": query_embedding},
               {"name": "@num_results", "value": num_results},
               {"name": "@similarity_score", "value": similarity_score}
           ]
       )
       similar_products = []
       async for result in query_results:
           similar_products.append(result)
       formatted_results = [{'similarity_score': product.pop('similarity_score'), 'product': product} for product in similar_products]
       return formatted_results
   ```

2. Next, create a method named `get_similar_products` that will serve as the function used by the LLM to perform vector searches against your database:

   ```python
   async def get_similar_products(message: str, num_results: int):
       """Retrieve similar products based on a user message."""
       # Vectorize the message
       embedding = await generate_embeddings(message)
       # Perform vector search against products in Cosmos DB
       similar_products = await vector_search(embedding, num_results=num_results)
       return similar_products
   ```

    The `get_similar_products` function makes asynchronous calls to the `vector_search` function you defined above, as well as the `generate_embeddings` function you created in the previous exercise. Embeddings are generated on the incoming user message to allow it to be compared to vectors stored in the database using the built-in `VectorDistance` function in Cosmos DB.

3. To allow the LLM to use the new functions, you must update the `tools` array you created earlier, adding a function definition for the `get_similar_products` method:

   ```json
   {
       "type": "function",
       "function": {
           "name": "get_similar_products",
           "description": "Retrieve similar products based on a user message.",
           "parameters": {
               "type": "object",
               "properties": {
                   "message": {"type": "string", "description": "The user's message looking for similar products"},
                   "num_results": {"type": "integer", "description": "The number of similar products to return"}
               },
               "required": ["message"]
           }
       }
   }
   ```

4. You must also add code to handle the new function's output. Add the following `elif` condition to the code block that handles function call outputs:

   ```python
   elif call.function.name == "get_similar_products":
       func_response = await get_similar_products(**json.loads(call.function.arguments))
       messages.append(
           {
               "role": "tool",
               "tool_call_id": call.id,
               "name": call.function.name,
               "content": json.dumps(func_response)
           }
       )
   ```

    The completed block with now look like this:

   ```python
   # Handle function call outputs
   if response_message.tool_calls:
       for call in response_message.tool_calls:
           if call.function.name == "apply_discount":
               func_response = await apply_discount(**json.loads(call.function.arguments))
               messages.append(
                   {
                       "role": "tool",
                       "tool_call_id": call.id,
                       "name": call.function.name,
                       "content": func_response
                   }
               )
           elif call.function.name == "get_category_names":
               func_response = await get_category_names()
               messages.append(
                   {
                       "role": "tool",
                       "tool_call_id": call.id,
                       "name": call.function.name,
                       "content": json.dumps(func_response)
                   }
               )
           elif call.function.name == "get_similar_products":
               func_response = await get_similar_products(**json.loads(call.function.arguments))
               messages.append(
                   {
                       "role": "tool",
                       "tool_call_id": call.id,
                       "name": call.function.name,
                       "content": json.dumps(func_response)
                   }
               )
   else:
       print("No function calls were made by the model.")
   ```

5. Lastly, you need to update the system prompt definition to provide instructions on how to perform vector searches. Insert the following at the bottom of the `system_prompt`:

   ```plaintext
   When asked to provide a list of products, you should:
       - Provide at least 3 candidate products unless the user asks for more or less, then use that number. Always include each product's name, description, price, and SKU. If the product has a discount, include it as a percentage and the associated sale price.
   ```

    The updated system prompt will be similar to:

   ```python
   system_prompt = """
   You are an intelligent copilot for Cosmic Works designed to help users manage and find bicycle-related products.
   You are helpful, friendly, and knowledgeable, but can only answer questions about Cosmic Works products.
   If asked to apply a discount:
       - Apply the specified discount to all products in the specified category. If the user did not provide you with a discount percentage and a product category, prompt them for the details you need to apply a discount.
       - Discount amounts should be specified as a decimal value (e.g., 0.1 for 10% off).
   If asked to remove discounts from a category:
       - Remove any discounts applied to products in the specified category by setting the discount value to 0.
   When asked to provide a list of products, you should:
       - Provide at least 3 candidate products unless the user asks for more or less, then use that number. Always include each product's name, description, price, and SKU. If the product has a discount, include it as a percentage and the associated sale price.
   """
   ```

6. Save the `main.py` file.

## Test the vector search feature

1. Restart the API app by running the following in the open integrated terminal window for that app in Visual Studio Code:

   ```bash
   uvicorn main:app
   ```

2. The UI should still be running, but if you stopped it, return to the integrated terminal window for it and run:

   ```bash
   python -m streamlit run index.py
   ```

3. Return to the browser window running the UI, and at the chat prompt, enter the following:

   ```bash
   Tell me about the mountain bikes in stock
   ```

    This question will return a few products that match your search.

4. Try a few other searches, such as "Show me durable pedals," "Provide a list of 5 stylish jerseys," and "Give me details about all gloves suitable for warm weather riding."

    For the last two queries, observe that the products contain the 15% discount and sale price you applied previously.
