import styles from './event-timeline.module.css';
import { useSimulation } from '../simulation/simulation-context';
import { EventItem } from './event-item';

export function EventTimeline() {
    const { state } = useSimulation();
    const timeline = state.timeline;

     if (timeline.length === 0) {
    return (
      <div className={styles.empty}>
        Waiting for events…
      </div>
    );
  }

    return (
    <div className={styles.timeline}>
      {timeline.map((event) => (
        <EventItem key={event.id} event={event} />
      ))}
    </div>
    );
}