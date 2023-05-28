const { ServiceBroker } = require("moleculer");

const uuid = require("uuid4");

const ID = uuid();

const { Database } = require("sqlite3");

const express = require("express");

const app = express();

const dbclass = new require("./database");

const db = new dbclass();

app.use(express.json());

app.get("/", (req, res, next) => {
    const {} = req;
});

const port = parseInt(process.env.PORT || 8080);

const tcpPort = parseInt(process.env.TCP_PORT || 7000);

const broker = new ServiceBroker({
    nodeID: ID,
    transporter: {
        type: "TCP",
        options: {
            udpDiscovery: false,
            port: tcpPort,
            debug: Boolean(process.env.MOLECULER_DEBUG),
            useHostname: true,
        },
    },
});

broker.createService({
    name: "example",
});

async function watchHosts() {
    const __hosts = new Set();
    __hosts.add(ID);
    const host = process.env.INSTANCE_IP || require("os").hostname();
    await db.addHost({ id: ID, host, tcpPort });
    setInterval(async () => {
        console.log({ nodes: broker.registry.nodes.toArray() });
        const hosts = await db.getHosts();
        for (const host of hosts) {
            if (__hosts.has(host.id)) {
                continue;
            }
            __hosts.add(host.id);
            if (!Boolean(process.env.SKIP_NODE_CONNECT)) {
                broker.transit?.tx?.addOfflineNode(
                    host.id,
                    host.host,
                    host.tcpPort
                );
            }
        }
    }, 5000);
}

app.listen(port, async () => {
    await Promise.all([broker.start(), watchHosts()]);
    console.log(`listening on ${port}`);
});
