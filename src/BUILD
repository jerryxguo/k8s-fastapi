# Turns each line of requirements.txt into an individually addressable
# target, e.g. `src:reqs#gunicorn` -- used by src/app/BUILD to depend on
# exactly the third-party packages a given target needs instead of the
# whole resolve.
python_requirements(
    name="reqs",
    resolve="k8s_python_default",
)
