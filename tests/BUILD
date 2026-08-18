python_tests(
    name="tests",
    resolve="k8s_python_default",
    dependencies=[
        "src:reqs#httpx",  # FastAPI's TestClient is httpx-based
    ],
)

python_test_utils(
    name="test_utils",
    resolve="k8s_python_default",
)
