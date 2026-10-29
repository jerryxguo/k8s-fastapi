# Turns each line of requirements.txt into an individually addressable
# target, e.g. `src:reqs#gunicorn` -- used by src/app/BUILD to depend on
# exactly the third-party packages a given target needs instead of the
# whole resolve.
python_requirements(
    name="reqs",
    resolve="k8s_python_default",
    # `kombu` (Celery's messaging layer, e.g. kombu.exceptions.OperationalError)
    # is imported directly but installed only as a dependency of celery, which
    # pins a compatible version. Mapping it here lets Pants infer the
    # dependency without a second, separately-pinned requirement.
    module_mapping={"celery": ["celery", "kombu"]},
)
