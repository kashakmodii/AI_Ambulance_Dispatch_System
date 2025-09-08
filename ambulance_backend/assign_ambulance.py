# assign_ambulance.py
import firebase_admin
from firebase_admin import credentials, firestore
from geopy.distance import geodesic
import time

# path to your service account json
cred = credentials.Certificate("firebase_config/firebase_credentials.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

AVERAGE_SPEED_KMPH = 40  # adjust to your local avg speed

def assign_nearest_ambulance(patient_doc):
    data = patient_doc.to_dict()
    if not data or 'location' not in data:
        return

    patient_loc = (data['location']['lat'], data['location']['lng'])

    # fetch available ambulances
    ambulances = db.collection('ambulances').where('status', '==', 'available').stream()

    nearest = None
    shortest_km = float('inf')
    for amb in ambulances:
        amb_data = amb.to_dict()
        # try both possible field names
        if 'latitude' in amb_data and 'longitude' in amb_data:
            amb_loc = (amb_data['latitude'], amb_data['longitude'])
        elif 'location' in amb_data and isinstance(amb_data['location'], dict):
            amb_loc = (amb_data['location'].get('lat'), amb_data['location'].get('lng'))
        else:
            continue

        dist = geodesic(patient_loc, amb_loc).km
        if dist < shortest_km:
            shortest_km = dist
            nearest = (amb.id, amb_loc, amb_data)

    if not nearest:
        print(f"No available ambulance for {patient_doc.id}")
        # optionally set patient status to no_available
        db.collection('patient_requests').document(patient_doc.id).update({
            'status': 'no_available'
        })
        return

    amb_id, amb_loc, amb_data = nearest
    eta_min = round((shortest_km / AVERAGE_SPEED_KMPH) * 60)

    print(f"Assigning ambulance {amb_id} to patient {patient_doc.id} — {shortest_km:.2f} km, ETA {eta_min} min")

    # update ambulance doc: set assigned and assigned_patient
    db.collection('ambulances').document(amb_id).update({
        'status': 'assigned',
        'assigned_patient': patient_doc.id
    })

    # update patient request doc with assignment info
    db.collection('patient_requests').document(patient_doc.id).update({
        'status': 'ambulance_assigned',
        'assigned_ambulance': amb_id,
        'ambulance_latitude': amb_loc[0],
        'ambulance_longitude': amb_loc[1],
        'eta_minutes': eta_min
    })

def listener(doc_snapshot, changes, read_time):
    for change in changes:
        if change.type.name == 'ADDED':
            doc = change.document
            data = doc.to_dict() or {}
            # Only handle pending requests
            if data.get('status') == 'pending':
                assign_nearest_ambulance(doc)

if __name__ == "__main__":
    print("Assign ambulance listener started.")
    # Listen to new patient requests with status pending
    query = db.collection('patient_requests').where('status', '==', 'pending')
    query.on_snapshot(listener)

    # keep script alive
    while True:
        time.sleep(60)
