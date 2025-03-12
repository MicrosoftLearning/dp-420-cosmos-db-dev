---
lab:
    title: '07.4 - Implement RAG with LangChain and Azure Cosmos DB for NoSQL Vector Search'
    module: 'Build copilots with Python and Azure Cosmos DB for NoSQL'
---

# Implement RAG with LangChain and Azure Cosmos DB for NoSQL Vector Search

LangChain's orchestration capabilities bring a multitude of benefits over implementing your copilot's LLM integration using the Azure OpenAI client directly. LangChain allows for more seamless integration with various data sources, including Azure Cosmos DB, enabling efficient vector search that enhances the retrieval process. LangChain offers robust tools for managing and optimizing workflows, making it easier to build complex applications with modular and reusable components. This flexibility not only simplifies development but also ensures scalability and maintainability.

In this lab, you will enhance your copilot by transitioning your API's `/chat` endpoint from using the Azure OpenAI client to leveraging LangChain’s powerful orchestration capabilities. This shift will enable more efficient data retrieval and improved performance by integrating vector search functionality with Azure Cosmos DB for NoSQL. Whether you are looking to optimize your app's information retrieval process or simply explore the potential of RAG, this module will guide you through the seamless conversion, demonstrating how LangChain can streamline and elevate your app's capabilities. Let's embark on this journey to unlock new efficiencies and insights with LangChain and Azure Cosmos DB!

> &#128721; The previous exercises in this module are prerequisites for this lab. If you still need to complete any of those exercises, please finish them before continuing, as they provide the necessary infrastructure and starter code for this lab.

## Install the LangChain libraries

1. Using Visual Studio Code, open the folder into which you cloned the lab code repository for **Build copilots with Azure Cosmos DB** learning module.

2. In the **Explorer** pane within Visual Studio Code, browse to the **python/07-build-copilot** folder and open the `requirements.txt` file found within it.

3. Update the `requirements.txt` file to include the required LangChain libraries:

   ```ini
   langchain==0.3.9
   langchain-openai==0.2.11
   ```

4. Launch a new integrated terminal window in Visual Studio Code and change directories to `python/07-build-copilot`.

5. Ensure the integrated terminal window runs within your Python virtual environment by activating it using the appropriate command for your OS and shell from the following table:

    | Platform | Shell | Command to activate virtual environment |
    | -------- | ----- | --------------------------------------- |
    | POSIX | bash/zsh | `source .venv/bin/activate` |
    | | fish | `source .venv/bin/activate.fish` |
    | | csh/tcsh | `source .venv/bin/activate.csh` |
    | | pwsh | `.venv/bin/Activate.ps1` |
    | Windows | cmd.exe | `.venv\Scripts\activate.bat` |
    | | PowerShell | `.venv\Scripts\Activate.ps1` |

6. Update your virtual environment with the LangChain libraries by executing the following command at the integrated terminal prompt:

   ```bash
   pip install -r requirements.txt
   ```

7. Close the integrated terminal.

## Update the backend API

In the previous lab, you executed a RAG pattern using the Azure OpenAI client and data from Azure Cosmos DB. Now, you will update the backend API to use a LangChain agent with tools to perform the same actions.

Using LangChain to interact with language models deployed in your Azure OpenAI Service is somewhat simplier from a code standpoint...

1. Remove the `from openai import AzureOpenAI` import statement at the top of the `main.py` file. That client library is no longer needed, as all interactions with Azure OpenAI will go through LangChain-provided classes.

2. Delete the following import statements at the top of the `main.py` file, as they will no longer necessary:

   ```python
   from openai import AsyncAzureOpenAI
   import json
   ```

### Update embedding endpoint

1. Import the `AzureOpenAIEmbeddings` class from the `langchain_openai` library by adding the following import statement at the top of the `main.py` file:

   ```python
   from langchain_openai import AzureOpenAIEmbeddings
   ```

2. Locate the `generate_embeddings` method in the file and overwrite it with the following, which uses the `AzureOpenAIEmbeddings` class to handle interactions with Azure OpenAI:

   ```python
   async def generate_embeddings(text: str):
       """Generates embeddings for the provided text."""
       # Use LangChain's Azure OpenAI Embeddings class
       azure_openai_embeddings = AzureOpenAIEmbeddings(
           azure_deployment = EMBEDDING_DEPLOYMENT_NAME,
           azure_endpoint = AZURE_OPENAI_ENDPOINT,
           azure_ad_token_provider = get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")
       )
       return await azure_openai_embeddings.aembed_query(text)
   ```

    The `AzureOpenAIEmbeddings` class provides an interface for interacting with the Azure OpenAI Embeddings API, returning a simplified response object containing only the generated vector.

### Update chat endpoint

1. Update the `lanchain_openai` import statement to append the `AzureChatOpenAI` class:

   ```python
   from langchain_openai import AzureOpenAIEmbeddings, AzureChatOpenAI
   ```

1. Import the following additional LangChain objects that will be used when building out the revised `/chat` endpoint:

   ```python
   from langchain.agents import AgentExecutor, create_openai_functions_agent
   from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
   from langchain_core.tools import StructuredTool
   ```

1. The chat history will be injected into the copilot conversation differently using a LangChain agent, so delete the lines of code immediately following the `system_prompt` definition. The line you should delete are:

   ```python
   # Provide the copilot with a persona using the system prompt.
   messages = [{ "role": "system", "content": system_prompt }]

   # Add the chat history to the messages list
   for message in request.chat_history[-request.max_history:]:
       messages.append(message)

   # Add the current user message to the messages list
   messages.append({"role": "user", "content": request.message})
   ```

1. In place of the code you just deleted, define a `prompt` object using LangChain's `ChatPromptTemplate` class:

   ```python
   prompt = ChatPromptTemplate.from_messages(
       [
           ("system", system_prompt),
           MessagesPlaceholder("chat_history", optional=True),
           ("user", "{input}"),
           MessagesPlaceholder("agent_scratchpad")
       ]
   )
   ```

    The `ChatPromptTemplate` is being created with several components in a specific order. Here's how those peices fit together:

    - **System Message**: Uses the `system_prompt` to gives a persona to the copilot, providing instructions on how the assistant should behave and interact with users.
    - **Chat History**: Allows the `chat_history`, containing a list of past messages in the conversation, to be incorporated into the context over which the LLM is working.
    - **User Input**: The current user message.
    - **Agent Scratchpad**: Allows for intermediate notes or steps taken by the agent.

    The resulting prompt provides a structured input for the conversational AI agent, helping it to generate a response based on the given context.

1. Next, replace the `tools` array definition with the following, which uses LangChain's `StructuredTool` class to extract function definitions into the proper format:

   ```python
   tools = [
       StructuredTool.from_function(coroutine=apply_discount),
       StructuredTool.from_function(coroutine=get_category_names),
       StructuredTool.from_function(coroutine=get_similar_products)
   ]
   ```

    The `StructuredTool.from_function` method in LangChain creates a tool from a given function, using the input parameters and the function's docstring description. To use it with async methods, you specify pass the function name to the `coroutine` input parameter.

    In Python, a docstring (short for documentation string) is a special type of string used to document a function, method, class, or module. It provides a convenient way of associating documentation with Python code and is typically enclosed within triple quotes (""" or '''). Docstrings are placed immediately after the definition of the function (or method, class, or module) they document.

    Using this function automates the creation of the JSON function definitions you had to manually create using the Azure OpenAI client, simplifying the process of function calling.

1. Delete all of the code between the `tools` array definition you completed above and the `return` statement at the end of the function. Using the Azure OpenAI client, you had to make two calls the the language model. The first to allow it to determine what function calls, if any, it needs to make to augment the prompt, and the second to ask for a RAG completion. In between, you had to use code to inspect the response from the first call to determine if function calls were required, and then write code to "handle" calling those functions. You then had to insert the output of those function calls into the messages being sent to the LLM, so it could have the enriched prompt to reason of when formulating a completion response. LangChain greatly simplifies the process of calling an LLM using a RAG pattern, as you will see below. The code you should remove is:

   ```python
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

   # Second API call, asking the model to generate a response
   final_response = await aoai_client.chat.completions.create(
       model = COMPLETION_DEPLOYMENT_NAME,
       messages = messages
   )

   return final_response.choices[0].message.content
   ```

1. Working from just below the `tools` array definition, create a reference to the Azure OpenAI API using the `AzureChatOpenAI` class in LangChain:

   ```python
   # Connect to Azure OpenAI API
   azure_openai = AzureChatOpenAI(
       azure_deployment=COMPLETION_DEPLOYMENT_NAME,
       azure_endpoint=AZURE_OPENAI_ENDPOINT,
       azure_ad_token_provider=get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default"),
       api_version=AZURE_OPENAI_API_VERSION
   )
   ```

1. To allow your LangChain agent to interact with the functions you've defined, you will create an agent using the `create_openai_functions_agent` method, to which you will provide the `AzureChatOpenAI` objedt, `tools` array, and `ChatPromptTemplate` object:

   ```python
   agent = create_openai_functions_agent(llm=azure_openai, tools=tools, prompt=prompt)
   ```

    The `create_openai_functions_agent` function in LangChain creates an agent that can call external functions to perform tasks using a specified language model and tools. This enables the integration of various services and functionalities into the agent's workflow, providing flexibility and enhanced capabilities.

1. In LangChain, the `AgentExecutor` class is used to manage the execution flow of the agents, such as the one you created with the `create_openai_functions_agent` method. It handles the processing of inputs, the invocation of tools or models, and the handling of outputs. Use the below code to create an agent executor for your agent:

   ```python
   agent_executor = AgentExecutor(agent=agent, tools=tools, verbose=True, return_intermediate_steps=True)
   ```

    The `AgentExecutor` ensures that all the steps required to generate a response are executed in the correct order. It abstracts the complexities of execution for agents, providing an additional layer of functionality and structure, and making it easier to build, manage, and scale sophisticated agents.

1. You will use the agent executor's `invoke` method to send the incoming user message to the LLM. You will also include the chat history. Insert the following code below the `agent_executor` definition:

   ```python
   completion = await agent_executor.ainvoke({"input": request.message, "chat_history": request.chat_history[-request.max_history:]})
   ```

   The `input` and `chat_history` tokens were defined in the prompt object created using the `ChatPromptTemplate`. With the `invoke` method, these will be injected into the prompt, allowing the LLM to use that information when creating a response.

1. Finally, update the return statement to use the `output` of the agent's completion object:

   ```python
   return completion["output"]
   ```

1. Save the `main.py` file. The updated `/chat` endpoint function should now look like this:

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
       When asked to provide a list of products, you should:
           - Provide at least 3 candidate products unless the user asks for more or less, then use that number. Always include each product's name, description, price, and SKU. If the product has a discount, include it as a percentage and the associated sale price.
       """
       prompt = ChatPromptTemplate.from_messages(
           [
               ("system", system_prompt),
               MessagesPlaceholder("chat_history", optional=True),
               ("user", "{input}"),
               MessagesPlaceholder("agent_scratchpad")
           ]
       )
    
       # Define function calling tools
       tools = [
           StructuredTool.from_function(apply_discount),
           StructuredTool.from_function(get_category_names),
           StructuredTool.from_function(get_similar_products)
       ]
    
       # Connect to Azure OpenAI API
       azure_openai = AzureChatOpenAI(
           azure_deployment=COMPLETION_DEPLOYMENT_NAME,
           azure_endpoint=AZURE_OPENAI_ENDPOINT,
           azure_ad_token_provider=get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default"),
           api_version=AZURE_OPENAI_API_VERSION
       )
    
       agent = create_openai_functions_agent(llm=azure_openai, tools=tools, prompt=prompt)
       agent_executor = AgentExecutor(agent=agent, tools=tools, verbose=True, return_intermediate_steps=True)
        
       completion = await agent_executor.ainvoke({"input": request.message, "chat_history": request.chat_history[-request.max_history:]})
            
       return completion["output"]
   ```

## Start the API and UI apps

1. To start the API, open a new integrated terminal window in Visual Studio Code.

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

1. Open a new integrated terminal window, change directories to `python/07-build-copilot` to activate your Python environment, then change directories to the `ui` folder and run the following to start your UI app:

   ```bash
   python -m streamlit run index.py
   ```

1. If the UI does not open automatically in a browser window, launch a new browser tab or window and navigate to <http://localhost:8501> to open the UI.

## Test the copilot

1. Before sending messages into the UI, return to Visual Studio Code and select the integrated terminal window associated with the API app. Within this window, you will see the "verbose" ouptut generated by the LangChain agent executor, which provides insights into how LangChain is handling the requests you send in. Pay attention to the output in this window as you send in the below requests, checking back in after each call.

1. At the chat prompt in the UI, enter "Apply a discount" and send the message.

    You should receive a reply asking for the discount percentage you would like to appy, and for what product category.

1. Reply, "Gloves."

    You will receive a response asking for what discount percentage would you like to apply to the "Gloves" category.

1. Send a message of "25%."

    You should get a response of "A 25% discount has been successfully applied to all products in the "Gloves" category."

1. Ask the copilot to "show me all gloves."

    In the reply, you should see a list of all gloves in database, which will include the 25% discount price.

1. Finally, ask "What gloves are best cold weather riding?" to perform a vector search. This involves a function call to the `get_similar_items` method, which then calls both the `generate_embeddings` method you updated to use a LangChain implementation and the `vector_search` function.

1. Close the integrated terminal.

1. Close **Visual Studio Code**.
