## commands 

```
docker build . -t mypython:v1
docker images
```

```
docker run -d -p 9005:8080 mypython:v1

docker ps 
```

docker exec -it 5b0dd8ee504e /bin/bash

if the above does not work 

docker exec -it 5b0dd8ee504e  sh 


Docker push commands 

```
docker login -u <hubid>

then put the pwd
```
docker tag mypython:v1  vishwacloudlab/mypython:v1

docker push vishwacloudlab/mypython:v1