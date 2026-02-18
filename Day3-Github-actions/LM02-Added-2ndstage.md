
```
  build:
    runs-on: ubuntu-latest
    steps:
     - name: Set up Java 17
       uses: actions/setup-java@v4
       with:
         distribution: 'temurin'
         java-version: '17'

```