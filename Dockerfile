from --platform=amd64 node

copy index.js /app/
copy database.js /app/
copy package.json /app/

workdir /app

run npm install && npm install moleculer

#copy node_modules/moleculer /app/node_modules/

cmd ["node", "index.js"]
