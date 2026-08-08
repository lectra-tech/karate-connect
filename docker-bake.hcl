group "default" {
  targets = ["minimal", "nominal", "aks"]
}

target "builder" {
  context    = "."
  dockerfile = "Dockerfile_builder"
  tags       = ["karate-connect:builder"]
}

target "minimal" {
  context    = "."
  dockerfile = "Dockerfile_minimal"
  tags       = ["karate-connect:minimal"]
  contexts = {
    "karate-connect:builder" = "target:builder"
  }
  args = {
    BUILDER_IMAGE = "karate-connect:builder"
  }
}

target "python" {
  context    = "."
  dockerfile = "Dockerfile_python"
  tags       = ["karate-connect:python"]
  contexts = {
    "karate-connect:minimal" = "target:minimal"
  }
  args = {
    BASE_IMAGE = "karate-connect:minimal"
  }
}

target "nominal" {
  context    = "."
  dockerfile = "Dockerfile_nominal"
  tags       = ["karate-connect"]
  contexts = {
    "karate-connect:python" = "target:python"
  }
  args = {
    BASE_IMAGE = "karate-connect:python"
  }
}

target "aks" {
  context    = "."
  dockerfile = "Dockerfile_aks"
  tags       = ["karate-connect:aks"]
  contexts = {
    "karate-connect:python" = "target:python"
  }
  args = {
    BASE_IMAGE = "karate-connect:python"
  }
}

