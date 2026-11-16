"""Exercise Azure's actual Fabric/Invoke task-context boundary without SSH."""

import importlib
from types import SimpleNamespace

fabric = importlib.import_module("fabric")
invoke = importlib.import_module("invoke")
appservice = importlib.import_module("azure.cli.command_modules.appservice.custom")
tasks = importlib.import_module("fabric.tasks")

assert fabric.__version__ == "3.2.3"
assert invoke.__version__ == "3.0.3"
assert appservice.Connection is fabric.Connection
connection = appservice.Connection("localhost")
assert isinstance(connection, invoke.Context)
assert not connection.is_connected

# Invoke 3 passes the parser result into Fabric's task-context factory.
# Import/constructor-only tests do not detect the old factory signature.
call = tasks.ConnectionCall(
    fabric.Task(lambda context: context), init_kwargs={"host": "localhost"}
)
context = call.make_context(
    fabric.Config(), SimpleNamespace(remainder="offline-context-regression")
)
assert isinstance(context, fabric.Connection)
assert context.remainder == "offline-context-regression"
assert not context.is_connected
