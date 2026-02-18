

```
name: First GitHub Actions Workflow

on: 
  push:
    branches:
      - main

env:
    app_env: dev

jobs:
  hello-world:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Print Hello, World
        run: echo "🎉 Hello, GitHub Actions! you are on $app_env environment"
    
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Set up jaba 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
     
      - name: using env var agin
        run: echo "using env $app_env again"
```