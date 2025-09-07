import json
import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase
cred = credentials.Certificate("firebase_config/firebase_credentials.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Load hospital data
with open("hospitals_data.json", "r", encoding="utf-8") as file:
    hospitals = json.load(file)

# Reference to the Firestore collection
ambulance_ref = db.collection("ambulances")

# Upload each hospital's ambulance data
for hospital in hospitals:
    data = {
        "hospital_name": hospital["hospital_name"],
        "district": hospital["district"],
        "latitude": hospital["latitude"],
        "longitude": hospital["longitude"],
        "status": "available"  # Default status
    }
    ambulance_ref.add(data)
    print(f"✅ Added ambulance for {hospital['hospital_name']}")

print("🎯 All ambulance data uploaded successfully!")
