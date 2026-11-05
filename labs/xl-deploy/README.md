# XL Deploy: Setup and Detailed Worked Example

We deploy `javadocker\target\javadocker-sample-1.0.0.jar` to DEV and then UAT folders on an SSH target server. Everything runs in Docker.

> Not yet run: the Docker daemon was off when this was written. Start Docker Desktop first. If the image tag `24.1` is unavailable, check Docker Hub for the current `xebialabs/xl-deploy` (or `digitalai/deploy`) tag and edit the compose file. Some versions also need a license file.

## 1. Start the stack
```powershell
cd labs\xl-deploy
docker compose up -d
docker compose logs -f xl-deploy     # wait for "XL Deploy has started" (1-3 min)
```
- UI: http://localhost:4516, login `admin` / `admin123`
- Target server: host `target-server`, SSH port `2222`, user `deployer` / `deployer123`
```powershell
docker exec -u 0 target-server mkdir -p /opt/apps/dev /opt/apps/uat
docker exec -u 0 target-server chown -R 1000:1000 /opt/apps
```

## 2. Infrastructure (Library -> Infrastructure)
1. New -> `overthere.SshHost`: Name `target-server`, OS `UNIX`, Connection type `SFTP`, Address `target-server`, Port `2222`, Username `deployer`, Password `deployer123`.
2. Right-click the host -> **Check connection** (must succeed).

> **No separate folder container to create.** In this XL Deploy/Digital.ai Deploy version, `file.File`/`file.Folder` are **deployables**, not containers, and `overthere.SshHost` has no child "folder" container type. The host itself (`target-server`) is the container; the target directory is set as a **Target Path** property per deployment instead (step 5). If your README/notes mention adding a `file.Folder` container under the host, skip that step - it doesn't exist in this plugin version.

## 3. Environments
- `DEV` containing `Infrastructure/target-server`
- `UAT` containing `Infrastructure/target-server`

The same host CI can be a member of both environments - DEV and UAT never collide because each deployment sets its own Target Path (`/opt/apps/dev` vs. `/opt/apps/uat`).

## 4. Application and package
1. Applications -> New -> Application `javadocker-app`.
2. New -> Deployment package `1.0.0`.
3. In `1.0.0` add deployable `file.File` named `javadocker-jar`, upload `javadocker-sample-1.0.0.jar`. Leave **Target Path** blank here - you set it per environment in step 5.

## 5. Deploy to DEV
1. Deployment workspace: drag `javadocker-app/1.0.0` and `Environments/DEV`.
2. Confirm the generated mapping `javadocker-jar -> target-server`, click the mapped item, and set **Target Path** = `/opt/apps/dev` (set **Create Target Path** = true too if you skipped the `mkdir` in step 1).
3. **Preview** (see the generated steps), then **Execute**.
4. Verify:
```powershell
docker exec target-server ls -l /opt/apps/dev
```

## 6. Test the deployed jar
`target-server` has no Java runtime - XL Deploy only copies the artifact, it does not run it. To actually execute what was deployed and see the application's real output, run it in a throwaway container with a JRE:
```powershell
# Copy the deployed jar from the target server to your machine
docker cp target-server:/opt/apps/dev/javadocker-jar .\app.jar

# Run it, publishing its port 8080 to host port 8090
docker run --rm -d --name app-test -p 8090:8080 -v "${PWD}\app.jar:/app.jar" eclipse-temurin:17-jre java -jar /app.jar
Start-Sleep -Seconds 10
docker logs app-test --tail 20

# Hit the app's endpoints
curl http://localhost:8090/
curl http://localhost:8090/api/info

# Clean up the test container and local copy
docker rm -f app-test
Remove-Item .\app.jar
```
- `GET /` should render the "Java Docker Demo" HTML page - this proves the deployed jar actually runs.
- `GET /api/info` returns JSON build/runtime metadata. If it 404s, the deployed jar is an older local build without `ApiController`; rebuild with `mvn -f javadocker clean package` and redeploy.
- To test the UAT copy instead, change the `docker cp` source path to `/opt/apps/uat/javadocker-jar`.

> This is separate from XL Deploy's own output: the **Tasks** screen in the UI shows the step-by-step deployment log (what was copied, when, by whom) - useful for the audit trail, but it won't prove the artifact actually runs.

## 7. Promote to UAT
Repeat step 5 with `UAT`, setting **Target Path** = `/opt/apps/uat` this time, then check `/opt/apps/uat`. The same immutable package is reused, which is the release-automation principle.

## 8. Update and rollback
1. Create package `1.1.0` (upload a changed jar, or the same jar renamed).
2. Deploy `1.1.0` to DEV: XL Deploy produces an **update** plan.
3. Roll back by deploying `1.0.0` again, or use **Rollback** on the task screen after a failed or stopped task.

## 9. As code (optional, XL CLI)
```yaml
apiVersion: xl-deploy/v1
kind: Applications
spec:
- name: javadocker-app
  type: udm.Application
  children:
  - name: 2.0.0
    type: udm.DeploymentPackage
    deployables:
    - name: javadocker-jar
      type: file.File
      file: !file ../../javadocker/target/javadocker-sample-1.0.0.jar
```
```powershell
xl apply -f app.yaml
```

## 10. Checklist
- [ ] Check connection is green
- [ ] Jar in `/opt/apps/dev`, then `/opt/apps/uat`
- [ ] Deployed jar actually runs and responds (step 6)
- [ ] Update and rollback done
- [ ] You can explain application, package, environment, deployment

## 11. Cleanup
```powershell
docker compose down -v
```

## Troubleshooting
| Symptom | Fix |
|---|---|
| Docker error about the pipe | Start Docker Desktop |
| UI unreachable | Wait; check `docker compose logs xl-deploy` |
| Startup stops on EULA/license | Keep `ACCEPT_EULA=Y`; add a license file if the version requires it |
| Check connection fails | Host `target-server`, port `2222`, credentials above |
| Permission denied on copy | Re-run the `chown` command in step 1 |
| Can't find a "folder container" option under the host | It doesn't exist in this version - `file.Folder`/`file.File` are deployables, not containers. Use the host as the container and set **Target Path** on the deployment mapping (step 5). |
