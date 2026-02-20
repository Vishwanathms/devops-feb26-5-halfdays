```
  run_test:
    name: Part 2 - Run pushed image + curl + wait
    needs: docker

    # Option A (recommended): your Ubuntu node (self-hosted runner)
    # runs-on: [self-hosted, linux, ubuntu]

    # Option B: GitHub-hosted Ubuntu runner (demo)
    runs-on: ubuntu-latest

    steps:
      # Recreate the same tag used in Job-1 (IMAGE_TAG from commit SHA)
      - name: Set image tag (same as build job)
        run: echo "IMAGE_TAG=${GITHUB_SHA::7}" >> $GITHUB_ENV

      - name: Show image details
        run: |
          echo "Image: ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }}"

      # Keep this if Docker Hub repo is PRIVATE.
      # If repo is PUBLIC, login is optional (still ok to keep).
      - name: Login to Docker Hub (for pull)
        run: echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login -u "${{ secrets.DOCKERHUB_USERNAME }}" --password-stdin

      - name: Pull the pushed image
        run: |
          docker pull ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }}

      - name: Run container
        run: |
          docker rm -f python-gha-lab || true
          docker run -d --name python-gha-lab -p 8080:8080 \
            -e APP_ENV=ci \
            ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }}
          docker ps -a

      - name: Curl output (wait until ready)
        run: |
          set -e
          echo "Waiting for app..."
          for i in {1..20}; do
            if curl -fsS http://localhost:8080/; then
              echo ""
              echo "✅ Curl success"
              exit 0
            fi
            echo "Not ready yet... retry $i/20"
            sleep 3
          done

          echo "❌ App not ready in time"
          docker logs python-gha-lab || true
          exit 1

      - name: Wait (hold container)
        run: |
          echo "Holding for 60 seconds..."
          sleep 60

      - name: Cleanup
        if: always()
        run: |
          docker rm -f python-gha-lab || true
```