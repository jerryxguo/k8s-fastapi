python_sources(
    name="src",
    resolve="k8s_python_default",
)

# gunicorn_conf.py is loaded by gunicorn itself via `-c python:app.gunicorn_conf`,
# not imported by other Python code -- Pants would otherwise not know it's a
# build input the pex_binary below needs, so it's declared as a resource and
# added as an explicit dependency instead of relying on import inference.
resource(
    name="gunicorn_config",
    source="gunicorn_conf.py",
)

pex_binary(
    name="app",
    entry_point="gunicorn",
    args=[
        "app.main:app",
        "-c",
        "python:app.gunicorn_conf",
    ],
    resolve="k8s_python_default",
    dependencies=[
        ":src",
        ":gunicorn_config",
        "src:reqs#gunicorn",
        "src:reqs#uvicorn",
    ],
    include_tools=True,  # bundles `PEX_TOOLS=1 ... venv` support used by the Dockerfile
)

docker_image(
    name="docker",
    repository="k8s-demo-shared/service-api",
    image_tags=["latest", "{build_args.BUILD_VERSION}"],
)
