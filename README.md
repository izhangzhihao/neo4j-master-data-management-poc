# Neo4j-master-data-management-poc

# Install Neo4j

To dump an initial set of configuration files:

```bash
docker run --rm\
    --volume=$HOME/neo4j/conf:/conf \
    neo4j:2.3 dump-config
```

Set
 
```
dbms.security.auth_enabled=false
org.neo4j.server.webserver.address=0.0.0.0
```

Or Set env: `NEO4J_LOGIN` and `NEO4J_PASSWORD` for authenticating Neo4j by neocons

```bash
docker run \
    --publish=7474:7474 \
    --volume=$HOME/neo4j/data:/data \
    --volume=$HOME/neo4j/logs:/logs \
    --volume=$HOME/neo4j/conf:/conf \
    neo4j:2.3
```

# Install [Leiningen](http://leiningen.org/)

# Run `lein repl` in "stackoverflow-graphgist"

# Execute `(stackoverflow-graphgist.core/-main)`

# Import github neo4j data into neo4j

```bash
cd github-neo4j-community
brew install libtool
brew install autoconf
brew install automake
bundle install
GITHUB_TOKEN=<token> NEO4J_URL=http://localhost:7474/db/data/ bundle exec ruby run.rb
```



[Making Master Data Management Fun with Neo4j - Part 1](http://blog.brian-underwood.codes/2015/02/16/making_master_data_management_fun_with_neo4j_-_part_1/)

[Making Master Data Management Fun with Neo4j - Part 2](http://blog.brian-underwood.codes/2015/02/22/making_master_data_management_fun_with_neo4j_-_part_2/)

[Making Master Data Management Fun with Neo4j - Part 3](http://blog.brian-underwood.codes/2015/03/08/making_master_data_management_fun_with_neo4j_-_part_3/)