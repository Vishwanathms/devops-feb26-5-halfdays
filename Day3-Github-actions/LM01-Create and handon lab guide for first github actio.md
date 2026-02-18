# Create and handon lab guide for first github actions yaml file with execution steps

Here’s a practical, step-by-step **hand-on lab guide** to create and execute your **first GitHub Actions workflow (YAML) file**:

## 🏁 Step 1: Create or Open a GitHub Repository

- Go to [github.com](https://github.com), log in, and create a new repository (or use an existing one).


## 📝 Step 2: Add Your First GitHub Actions Workflow

### Using the GitHub Web Interface

1. Go to your repository main page.
2. Click the **Actions** tab.
3. Select “set up a workflow yourself” (or choose the “Simple Workflow”).
4. This opens an editor to create a `.yml` file under `.github/workflows`.

### Locally via Git and IDE

1. Inside your repo, create a directory:

```
mkdir -p .github/workflows
```

2. Inside `.github/workflows`, create a file, e.g. `first-action.yml`.

## ✏️ Step 3: Write a Simple Workflow (YAML Example)

Paste the following into `.github/workflows/first-action.yml`:

```yaml
name: First GitHub Actions Workflow

on: [push]

jobs:
  hello-world:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Print Hello, World
        run: echo "🎉 Hello, GitHub Actions!"
```


## 💾 Step 4: Commit and Push

- If you used the web UI, click **Start commit** or **Commit changes**.
- If local:

```sh
git add .github/workflows/first-action.yml
git commit -m "Add first GitHub Actions workflow"
git push
```


## 🚦 Step 5: Trigger and Observe Execution

1. Any push to the repository (including this commit) **automatically triggers the workflow**.
2. Go to the **Actions** tab in your repository.
3. You’ll see a workflow run triggered by your commit.
4. Click on the workflow run to see “hello-world” job, then expand steps to view log output—the “Print Hello, World” step should show your echo message.

## 🧑🔬 Step 6: Experiment

- Change the echo message, commit and push again—see it trigger.
- Try adding another step, for example:

```yaml
- name: List files
  run: ls -l
```


## 📝 What You Learned

- How to set up a workflow folder and YAML file.
- Workflow triggers (`on: [push]`), job setup, and basic steps.
- Checked results/logs in the Actions tab.

**You’ve successfully built and run your first GitHub Actions pipeline!**
As next steps, try expanding the workflow: add test steps, deploy scripts, or use marketplace actions for more advanced automation.

<div style="text-align: center">⁂</div>

[^1]: https://docs.github.com/actions/quickstart

[^2]: https://codefresh.io/learn/github-actions/github-actions-tutorial-and-examples/

[^3]: https://www.freecodecamp.org/news/learn-to-use-github-actions-step-by-step-guide/

[^4]: https://resources.github.com/learn/pathways/automation/advanced/building-your-first-custom-github-action/

[^5]: https://spacelift.io/blog/github-actions-tutorial

[^6]: https://www.geeksforgeeks.org/git/github-actions/

[^7]: https://dev.to/jethanivijay/devops-with-github-actions-hands-on-labs-1aa3

[^8]: https://dev.to/sre_panchanan/hello-world-in-github-actions-a-beginners-guide-to-your-first-workflow-1mbh

[^9]: https://docs.github.com/articles/getting-started-with-github-actions

[^10]: https://github.com/services/actions-training

[^11]: https://www.youtube.com/watch?v=ylEy4eLdhFs

[^12]: https://docs.github.com/en/actions/tutorials

[^13]: https://www.appsecengineer.com/courses-collection/github-actions-for-devsecops

[^14]: https://docs.github.com/actions/reference/workflow-syntax-for-github-actions

[^15]: https://www.learnenough.com/blog/git-actions-tutorial

[^16]: https://www.youtube.com/watch?v=Tz7FsunBbfQ

[^17]: https://blog.devops.dev/a-complete-guide-to-creating-github-actions-pipeline-with-yaml-templates-c57f2dbc2d0c

[^18]: https://kodekloud.com/courses/github-actions

[^19]: https://learn.microsoft.com/en-us/dotnet/devops/create-dotnet-github-action

[^20]: https://github.com/topics/hands-on-lab

