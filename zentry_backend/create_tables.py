from database import Base, engine
import models

Base.metadata.create_all(bind=engine)

print("SUCCESS: Zentry database tables created.")
print("Tables:", list(Base.metadata.tables.keys()))