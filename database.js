const { Database } = require('sqlite3');
const util = require('util');

class Instances extends Database {
	constructor() {
		super('./instances.db');
		if (process.env.CLEAN_TRY) {
			this.exec('drop table if exists instances;');
		}
		this.exec('create table if not exists instances (id varchar(50) primary key, host varchar(50) not null, tcpPort integer not null);');
		this.get = util.promisify(this.all.bind(this));
		this.add = util.promisify(this.run.bind(this));
	}

	async addHost({ id, host, tcpPort }) {
		await this.add('insert into instances(id, host, tcpPort) values(?, ?, ?)', [id, host, tcpPort]);
	}

	async getHosts() {
		return this.get('select * from instances');
	}

}


module.exports = Instances;
